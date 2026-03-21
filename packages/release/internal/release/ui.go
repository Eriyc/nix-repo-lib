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

	model := newCommandPickerModel(versionFile.Version, options)
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
	if execution.DryRun {
		parts = append(parts, "--dry-run")
	}
	if execution.Commit {
		parts = append(parts, "--commit")
	}
	if execution.Tag {
		parts = append(parts, "--tag")
	}
	if execution.Push {
		parts = append(parts, "--push")
	}
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
		"  dry run:       "+yesNo(execution.DryRun),
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
	current   Version
	options   []CommandOption
	cursor    int
	width     int
	height    int
	confirmed bool
	selected  CommandOption
}

func newCommandPickerModel(current Version, options []CommandOption) commandPickerModel {
	return commandPickerModel{
		current: current,
		options: options,
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
		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down", "j":
			if m.cursor < len(m.options)-1 {
				m.cursor++
			}
		case "enter":
			m.confirmed = true
			m.selected = m.options[m.cursor]
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m commandPickerModel) View() string {
	if len(m.options) == 0 {
		return "No release commands available.\n"
	}

	preview := m.options[m.cursor].Preview
	header := fmt.Sprintf("Release command picker\nCurrent version: %s\nUse up/down or j/k to choose, Enter to run, q to cancel.\n", m.current.String())

	listLines := make([]string, 0, len(m.options)+1)
	listLines = append(listLines, "Commands")
	for i, option := range m.options {
		cursor := "  "
		if i == m.cursor {
			cursor = "> "
		}
		listLines = append(listLines, fmt.Sprintf("%s%s\n  %s", cursor, option.Command, option.Description))
	}
	list := strings.Join(listLines, "\n")

	if m.width >= 100 {
		return header + "\n" + renderColumns(list, preview, m.width)
	}
	return header + "\n" + list + "\n\n" + preview + "\n"
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
