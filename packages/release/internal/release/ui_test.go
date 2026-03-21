package release

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func TestBuildCommandOptionsForStableVersion(t *testing.T) {
	t.Parallel()

	current := MustParseVersion(t, "1.0.0")
	options := BuildCommandOptions(Config{
		AllowedChannels:  []string{"alpha", "beta"},
		ReleaseStepsJSON: `[{"kind":"writeFile","path":"VERSION.txt","text":"$FULL_VERSION\n"}]`,
		PostVersion:      "echo post",
		Execution: ExecutionOptions{
			Commit: true,
			Tag:    true,
			Push:   true,
		},
	}, current)

	want := map[string]string{
		"release patch":      "1.0.1",
		"release minor":      "1.1.0",
		"release major":      "2.0.0",
		"release alpha":      "1.0.1-alpha.1",
		"release minor beta": "1.1.0-beta.1",
	}

	for command, nextVersion := range want {
		option, ok := findOptionByCommand(options, command)
		if !ok {
			t.Fatalf("expected command %q in options", command)
		}
		if option.NextVersion.String() != nextVersion {
			t.Fatalf("%s next version = %q, want %q", command, option.NextVersion.String(), nextVersion)
		}
		if !strings.Contains(option.Preview, "Release steps: yes") {
			t.Fatalf("%s preview missing release steps marker:\n%s", command, option.Preview)
		}
		if !strings.Contains(option.Preview, "Post-version:  yes") {
			t.Fatalf("%s preview missing post-version marker:\n%s", command, option.Preview)
		}
		if !strings.Contains(option.Preview, "git push:      yes") {
			t.Fatalf("%s preview missing git push marker:\n%s", command, option.Preview)
		}
	}
}

func TestBuildCommandOptionsForPrereleaseVersion(t *testing.T) {
	t.Parallel()

	current := MustParseVersion(t, "1.2.3-beta.2")
	options := BuildCommandOptions(Config{
		AllowedChannels: []string{"alpha", "beta", "rc"},
	}, current)

	stableOption, ok := findOptionByCommand(options, "release stable")
	if !ok {
		t.Fatalf("expected release stable option")
	}
	if stableOption.NextVersion.String() != "1.2.3" {
		t.Fatalf("release stable next version = %q, want 1.2.3", stableOption.NextVersion.String())
	}

	betaOption, ok := findOptionByCommand(options, "release beta")
	if !ok {
		t.Fatalf("expected release beta option")
	}
	if betaOption.NextVersion.String() != "1.2.3-beta.3" {
		t.Fatalf("release beta next version = %q, want 1.2.3-beta.3", betaOption.NextVersion.String())
	}

	patchOption, ok := findOptionByCommand(options, "release patch")
	if !ok {
		t.Fatalf("expected release patch option")
	}
	if patchOption.NextVersion.String() != "1.2.4-beta.1" {
		t.Fatalf("release patch next version = %q, want 1.2.4-beta.1", patchOption.NextVersion.String())
	}
}

func TestCommandPickerSelectionForStableVersion(t *testing.T) {
	t.Parallel()

	model := newCommandPickerModel(Config{
		AllowedChannels: []string{"alpha", "beta"},
	}, MustParseVersion(t, "1.2.3"))

	model.bumpCursor = 1
	model.channelCursor = 0

	option, err := model.selectedOption()
	if err != nil {
		t.Fatalf("selectedOption(): %v", err)
	}
	if got := strings.Join(option.Args, " "); got != "minor" {
		t.Fatalf("selected args = %q, want %q", got, "minor")
	}
	if option.NextVersion.String() != "1.3.0" {
		t.Fatalf("next version = %q, want %q", option.NextVersion.String(), "1.3.0")
	}

	model.bumpCursor = 3
	model.channelCursor = 1

	option, err = model.selectedOption()
	if err != nil {
		t.Fatalf("selectedOption(channel only): %v", err)
	}
	if got := strings.Join(option.Args, " "); got != "alpha" {
		t.Fatalf("selected args = %q, want %q", got, "alpha")
	}
	if option.NextVersion.String() != "1.2.4-alpha.1" {
		t.Fatalf("next version = %q, want %q", option.NextVersion.String(), "1.2.4-alpha.1")
	}
}

func TestCommandPickerSelectionForPrereleaseVersion(t *testing.T) {
	t.Parallel()

	model := newCommandPickerModel(Config{
		AllowedChannels: []string{"alpha", "beta", "rc"},
	}, MustParseVersion(t, "1.2.3-beta.2"))

	model.bumpCursor = 3
	model.channelCursor = 0

	option, err := model.selectedOption()
	if err != nil {
		t.Fatalf("selectedOption(current prerelease): %v", err)
	}
	if got := strings.Join(option.Args, " "); got != "beta" {
		t.Fatalf("selected args = %q, want %q", got, "beta")
	}
	if option.NextVersion.String() != "1.2.3-beta.3" {
		t.Fatalf("next version = %q, want %q", option.NextVersion.String(), "1.2.3-beta.3")
	}

	model.channelCursor = 1

	option, err = model.selectedOption()
	if err != nil {
		t.Fatalf("selectedOption(promote): %v", err)
	}
	if got := strings.Join(option.Args, " "); got != "stable" {
		t.Fatalf("selected args = %q, want %q", got, "stable")
	}
	if option.NextVersion.String() != "1.2.3" {
		t.Fatalf("next version = %q, want %q", option.NextVersion.String(), "1.2.3")
	}

	model.bumpCursor = 0

	if _, err := model.selectedOption(); err == nil {
		t.Fatalf("selectedOption(patch stable from prerelease) succeeded, want error")
	}
}

func TestCommandPickerFocusMovesAcrossSections(t *testing.T) {
	t.Parallel()

	model := newCommandPickerModel(Config{
		AllowedChannels: []string{"alpha", "beta"},
	}, MustParseVersion(t, "1.2.3"))

	next, _ := model.Update(tea.KeyMsg{Type: tea.KeyDown})
	model = next.(commandPickerModel)
	if model.focusSection != 0 || model.focusIndex != 1 || model.bumpCursor != 0 {
		t.Fatalf("after first down: focusSection=%d focusIndex=%d bumpCursor=%d", model.focusSection, model.focusIndex, model.bumpCursor)
	}

	next, _ = model.Update(tea.KeyMsg{Type: tea.KeyDown})
	model = next.(commandPickerModel)
	next, _ = model.Update(tea.KeyMsg{Type: tea.KeyDown})
	model = next.(commandPickerModel)
	next, _ = model.Update(tea.KeyMsg{Type: tea.KeyDown})
	model = next.(commandPickerModel)
	if model.focusSection != 1 || model.focusIndex != 4 || model.channelCursor != 0 {
		t.Fatalf("after moving into channel section: focusSection=%d focusIndex=%d channelCursor=%d", model.focusSection, model.focusIndex, model.channelCursor)
	}

	next, _ = model.Update(tea.KeyMsg{Type: tea.KeySpace})
	model = next.(commandPickerModel)
	if model.channelCursor != 0 {
		t.Fatalf("space changed selection unexpectedly: channelCursor=%d", model.channelCursor)
	}

	next, _ = model.Update(tea.KeyMsg{Type: tea.KeyUp})
	model = next.(commandPickerModel)
	if model.focusSection != 0 || model.focusIndex != 3 || model.bumpCursor != 0 {
		t.Fatalf("after moving back up: focusSection=%d focusIndex=%d bumpCursor=%d", model.focusSection, model.focusIndex, model.bumpCursor)
	}

	next, _ = model.Update(tea.KeyMsg{Type: tea.KeySpace})
	model = next.(commandPickerModel)
	if model.bumpCursor != 3 {
		t.Fatalf("space did not update bump selection: bumpCursor=%d", model.bumpCursor)
	}
}

func findOptionByCommand(options []CommandOption, command string) (CommandOption, bool) {
	for _, option := range options {
		if option.Command == command {
			return option, true
		}
	}
	return CommandOption{}, false
}
