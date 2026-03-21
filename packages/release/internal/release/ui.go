package release

import (
	"fmt"
	"io"
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"golang.org/x/term"
)

type CommandOption struct {
	Title       string
	Description string
	Command     string
	Args        []string
	NextVersion Version
	Preview     string
}

func IsInteractiveTerminal(stdin io.Reader, stdout io.Writer) bool {
	in, inOK := stdin.(*os.File)
	out, outOK := stdout.(*os.File)
	if !inOK || !outOK {
		return false
	}
	return term.IsTerminal(int(in.Fd())) && term.IsTerminal(int(out.Fd()))
}

func SelectCommand(config Config) ([]string, bool, error) {
	r := &Runner{Config: config}
	rootDir, err := r.rootDir()
	if err != nil {
		return nil, false, err
	}

	versionFile, _, err := r.loadVersionFile(rootDir)
	if err != nil {
		return nil, false, err
	}

	options := BuildCommandOptions(config, versionFile.Version)
	if len(options) == 0 {
		return nil, false, fmt.Errorf("no release commands available for current version %s", versionFile.Version.String())
	}

	model := newCommandPickerModel(config, versionFile.Version)
	finalModel, err := tea.NewProgram(model, tea.WithAltScreen()).Run()
	if err != nil {
		return nil, false, err
	}

	result := finalModel.(commandPickerModel)
	if !result.confirmed {
		return nil, false, nil
	}
	return append([]string(nil), result.selected.Args...), true, nil
}

func BuildCommandOptions(config Config, current Version) []CommandOption {
	var options []CommandOption
	seen := map[string]struct{}{}
	for _, args := range candidateCommandArgs(current, config.AllowedChannels) {
		command := formatReleaseCommand(args)
		if _, exists := seen[command]; exists {
			continue
		}

		next, err := ResolveNextVersion(current, args, config.AllowedChannels)
		if err != nil {
			continue
		}

		options = append(options, CommandOption{
			Title:       titleForArgs(args),
			Description: descriptionForArgs(current, args, next),
			Command:     command,
			Args:        append([]string(nil), args...),
			NextVersion: next,
			Preview:     buildPreview(config, current, args, next),
		})
		seen[command] = struct{}{}
	}
	return options
}

func candidateCommandArgs(current Version, allowedChannels []string) [][]string {
	candidates := [][]string{
		{"patch"},
		{"minor"},
		{"major"},
	}
	if current.Channel != "stable" {
		candidates = append([][]string{{"stable"}}, candidates...)
	}
	for _, channel := range allowedChannels {
		candidates = append(candidates,
			[]string{channel},
			[]string{"minor", channel},
			[]string{"major", channel},
		)
	}
	return candidates
}

func formatReleaseCommand(args []string) string {
	return formatReleaseCommandWithExecution(args, ExecutionOptions{})
}

func formatReleaseCommandWithExecution(args []string, execution ExecutionOptions) string {
	var parts []string
	parts = append(parts, "release")
	if len(args) == 0 {
		return strings.Join(parts, " ")
	}
	return strings.Join(append(parts, args...), " ")
}

func titleForArgs(args []string) string {
	if len(args) == 0 {
		return "Patch release"
	}

	switch len(args) {
	case 1:
		switch args[0] {
		case "patch":
			return "Patch release"
		case "minor":
			return "Minor release"
		case "major":
			return "Major release"
		case "stable":
			return "Promote to stable"
		default:
			return strings.ToUpper(args[0][:1]) + args[0][1:] + " prerelease"
		}
	case 2:
		return capitalize(args[0]) + " " + args[1]
	default:
		return strings.Join(args, " ")
	}
}

func descriptionForArgs(current Version, args []string, next Version) string {
	switch len(args) {
	case 1:
		switch args[0] {
		case "patch":
			return "Bump patch and keep the current channel."
		case "minor":
			return "Bump minor and keep the current channel."
		case "major":
			return "Bump major and keep the current channel."
		case "stable":
			return "Promote the current prerelease to a stable release."
		default:
			if current.Channel == args[0] && current.Channel != "stable" {
				return "Advance the current prerelease number."
			}
			return "Switch to the " + args[0] + " channel."
		}
	case 2:
		return fmt.Sprintf("Bump %s and publish to %s.", args[0], args[1])
	default:
		return "Release " + next.String() + "."
	}
}

func buildPreview(config Config, current Version, args []string, next Version) string {
	execution := config.Execution.Normalize()
	var lines []string
	lines = append(lines,
		"Command",
		"  "+formatReleaseCommandWithExecution(args, execution),
		"",
		"Version",
		"  Current: "+current.String(),
		"  Next:    "+next.String(),
		"  Tag:     "+next.Tag(),
		"",
		"Flow",
		"  Release steps: "+yesNo(strings.TrimSpace(config.ReleaseStepsJSON) != ""),
		"  Post-version:  "+yesNo(strings.TrimSpace(config.PostVersion) != ""),
		"  nix fmt:       yes",
		"  git commit:    "+yesNo(execution.Commit),
		"  git tag:       "+yesNo(execution.Tag),
		"  git push:      "+yesNo(execution.Push),
	)
	return strings.Join(lines, "\n")
}

func yesNo(v bool) string {
	if v {
		return "yes"
	}
	return "no"
}

func capitalize(s string) string {
	if s == "" {
		return s
	}
	runes := []rune(s)
	first := runes[0]
	if first >= 'a' && first <= 'z' {
		runes[0] = first - 32
	}
	return string(runes)
}

type commandPickerModel struct {
	config         Config
	current        Version
	width          int
	height         int
	focusSection   int
	focusIndex     int
	bumpOptions    []selectionOption
	channelOptions []selectionOption
	bumpCursor     int
	channelCursor  int
	confirmed      bool
	selected       CommandOption
	err            string
}

type selectionOption struct {
	Label string
	Value string
}

func newCommandPickerModel(config Config, current Version) commandPickerModel {
	return commandPickerModel{
		config:         config,
		current:        current,
		bumpOptions:    buildBumpOptions(current),
		channelOptions: buildChannelOptions(current, config.AllowedChannels),
	}
}

func (m commandPickerModel) Init() tea.Cmd {
	return nil
}

func (m commandPickerModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q", "esc":
			return m, tea.Quit
		case "up", "k", "shift+tab":
			m.moveFocus(-1)
		case "down", "j", "tab":
			m.moveFocus(1)
		case " ":
			m.selectFocused()
		case "enter":
			option, err := m.selectedOption()
			if err != nil {
				m.err = err.Error()
				return m, nil
			}
			m.confirmed = true
			m.selected = option
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m commandPickerModel) View() string {
	if len(m.bumpOptions) == 0 || len(m.channelOptions) == 0 {
		return "No release commands available.\n"
	}

	preview := m.preview()
	header := fmt.Sprintf("Release command picker\nCurrent version: %s\nUse up/down to move through options, Space to select, Enter to run, q to cancel.\n", m.current.String())
	sections := strings.Join([]string{
		m.renderSection("Bump type", m.bumpOptions, m.bumpCursor, m.focusSection == 0, m.focusedOptionIndex()),
		"",
		m.renderSection("Channel", m.channelOptions, m.channelCursor, m.focusSection == 1, m.focusedOptionIndex()),
	}, "\n")

	if m.width >= 100 {
		return header + "\n" + renderColumns(sections, preview, m.width)
	}
	return header + "\n" + sections + "\n\n" + preview + "\n"
}

func buildBumpOptions(current Version) []selectionOption {
	options := []selectionOption{
		{Label: "Patch", Value: "patch"},
		{Label: "Minor", Value: "minor"},
		{Label: "Major", Value: "major"},
	}
	if current.Channel != "stable" {
		options = append(options, selectionOption{
			Label: "None",
			Value: "",
		})
		return options
	}
	options = append(options, selectionOption{
		Label: "None",
		Value: "",
	})
	return options
}

func buildChannelOptions(current Version, allowedChannels []string) []selectionOption {
	options := []selectionOption{{
		Label: "Current",
		Value: current.Channel,
	}}
	if current.Channel != "stable" {
		options = append(options, selectionOption{
			Label: "Stable",
			Value: "stable",
		})
	}
	for _, channel := range allowedChannels {
		if channel == current.Channel {
			continue
		}
		options = append(options, selectionOption{
			Label: capitalize(channel),
			Value: channel,
		})
	}
	return options
}

func (m *commandPickerModel) moveFocus(delta int) {
	total := len(m.bumpOptions) + len(m.channelOptions)
	if total == 0 {
		return
	}

	index := wrapIndex(m.focusIndex+delta, total)
	m.focusIndex = index

	if index < len(m.bumpOptions) {
		m.focusSection = 0
		return
	}

	m.focusSection = 1
}

func (m *commandPickerModel) selectFocused() {
	if m.focusSection == 0 {
		m.bumpCursor = m.focusedOptionIndex()
		return
	}
	m.channelCursor = m.focusedOptionIndex()
}

func wrapIndex(idx int, size int) int {
	if size == 0 {
		return 0
	}
	for idx < 0 {
		idx += size
	}
	return idx % size
}

func (m commandPickerModel) focusedOptionIndex() int {
	if m.focusSection == 0 {
		return m.focusIndex
	}
	return m.focusIndex - len(m.bumpOptions)
}

func (m commandPickerModel) renderSection(title string, options []selectionOption, cursor int, focused bool, focusedIndex int) string {
	lines := []string{title}
	for i, option := range options {
		pointer := " "
		if focused && i == focusedIndex {
			pointer = ">"
		}
		radio := "( )"
		if i == cursor {
			radio = "(*)"
		}
		lines = append(lines, fmt.Sprintf("%s %s %s", pointer, radio, option.Label))
	}
	return strings.Join(lines, "\n")
}

func (m commandPickerModel) selectedArgs() []string {
	bump := m.bumpOptions[m.bumpCursor].Value
	channel := m.channelOptions[m.channelCursor].Value

	if bump == "" {
		if channel == "stable" {
			return []string{"stable"}
		}
		if channel == m.current.Channel {
			if channel == "stable" {
				return nil
			}
			return []string{channel}
		}
		return []string{channel}
	}

	if channel == m.current.Channel || (channel == "stable" && m.current.Channel == "stable") {
		return []string{bump}
	}
	return []string{bump, channel}
}

func (m commandPickerModel) selectedOption() (CommandOption, error) {
	args := m.selectedArgs()
	next, err := ResolveNextVersion(m.current, args, m.config.AllowedChannels)
	if err != nil {
		return CommandOption{}, err
	}
	return CommandOption{
		Title:       titleForArgs(args),
		Description: descriptionForArgs(m.current, args, next),
		Command:     formatReleaseCommand(args),
		Args:        append([]string(nil), args...),
		NextVersion: next,
		Preview:     buildPreview(m.config, m.current, args, next),
	}, nil
}

func (m commandPickerModel) preview() string {
	option, err := m.selectedOption()
	if err != nil {
		lines := []string{
			"Command",
			"  " + formatReleaseCommand(m.selectedArgs()),
			"",
			"Selection",
			"  " + err.Error(),
		}
		if m.err != "" {
			lines = append(lines, "", "Error", "  "+m.err)
		}
		return strings.Join(lines, "\n")
	}
	return option.Preview
}

func renderColumns(left string, right string, width int) string {
	if width < 40 {
		return left + "\n\n" + right
	}

	leftWidth := width / 2
	rightWidth := width - leftWidth - 3
	leftLines := strings.Split(left, "\n")
	rightLines := strings.Split(right, "\n")
	maxLines := len(leftLines)
	if len(rightLines) > maxLines {
		maxLines = len(rightLines)
	}

	var b strings.Builder
	for i := 0; i < maxLines; i++ {
		leftLine := ""
		if i < len(leftLines) {
			leftLine = leftLines[i]
		}
		rightLine := ""
		if i < len(rightLines) {
			rightLine = rightLines[i]
		}
		b.WriteString(padRight(trimRunes(leftLine, leftWidth), leftWidth))
		b.WriteString(" | ")
		b.WriteString(trimRunes(rightLine, rightWidth))
		b.WriteByte('\n')
	}
	return b.String()
}

func padRight(s string, width int) string {
	missing := width - len([]rune(s))
	if missing <= 0 {
		return s
	}
	return s + strings.Repeat(" ", missing)
}

func trimRunes(s string, width int) string {
	runes := []rune(s)
	if len(runes) <= width {
		return s
	}
	if width <= 1 {
		return string(runes[:width])
	}
	if width <= 3 {
		return string(runes[:width])
	}
	return string(runes[:width-3]) + "..."
}
