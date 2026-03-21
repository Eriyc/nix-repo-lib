package release

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestResolveNextVersion(t *testing.T) {
	t.Parallel()

	allowed := []string{"alpha", "beta", "rc", "internal"}
	tests := []struct {
		name    string
		current string
		args    []string
		want    string
		wantErr string
	}{
		{
			name:    "channel only from stable bumps patch",
			current: "1.0.0",
			args:    []string{"beta"},
			want:    "1.0.1-beta.1",
		},
		{
			name:    "explicit minor bump keeps requested bump",
			current: "1.0.0",
			args:    []string{"minor", "beta"},
			want:    "1.1.0-beta.1",
		},
		{
			name:    "full promotes prerelease to stable",
			current: "1.1.5-beta.1",
			args:    []string{"full"},
			want:    "1.1.5",
		},
		{
			name:    "set stable from prerelease requires full",
			current: "1.1.5-beta.1",
			args:    []string{"set", "1.1.5"},
			wantErr: "promote using 'stable' or 'full' only",
		},
		{
			name:    "patch stable from prerelease requires full",
			current: "1.1.5-beta.1",
			args:    []string{"patch", "stable"},
			wantErr: "promote using 'stable' or 'full' only",
		},
		{
			name:    "full no-op fails",
			current: "1.1.5",
			args:    []string{"full"},
			wantErr: "Version 1.1.5 is already current; nothing to do.",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			current, err := ParseVersion(tc.current)
			if err != nil {
				t.Fatalf("ParseVersion(%q): %v", tc.current, err)
			}

			got, err := ResolveNextVersion(current, tc.args, allowed)
			if tc.wantErr != "" {
				if err == nil {
					t.Fatalf("ResolveNextVersion(%q, %v) succeeded, want error", tc.current, tc.args)
				}
				if !strings.Contains(err.Error(), tc.wantErr) {
					t.Fatalf("ResolveNextVersion(%q, %v) error = %q, want substring %q", tc.current, tc.args, err.Error(), tc.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("ResolveNextVersion(%q, %v): %v", tc.current, tc.args, err)
			}
			if got.String() != tc.want {
				t.Fatalf("ResolveNextVersion(%q, %v) = %q, want %q", tc.current, tc.args, got.String(), tc.want)
			}
		})
	}
}

func TestVersionFileMetadataRoundTrip(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	path := filepath.Join(dir, "VERSION")
	content := strings.Join([]string{
		"1.0.0",
		"stable",
		"0",
		"desktop_backend_change_scope=bindings",
		"desktop_release_mode=binary",
		"desktop_unused=temporary",
		"",
	}, "\n")
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("WriteFile(VERSION): %v", err)
	}

	file, err := ReadVersionFile(path)
	if err != nil {
		t.Fatalf("ReadVersionFile: %v", err)
	}

	if got := file.Current().String(); got != "1.0.0" {
		t.Fatalf("Current() = %q, want 1.0.0", got)
	}
	if got := file.Metadata.Get("desktop_backend_change_scope"); got != "bindings" {
		t.Fatalf("Metadata.Get(scope) = %q, want bindings", got)
	}

	file.Version = MustParseVersion(t, "1.0.1")
	file.Metadata.Set("desktop_release_mode", "codepush")
	file.Metadata.Set("desktop_binary_version_min", "1.0.0")
	file.Metadata.Set("desktop_binary_version_max", "1.0.1")
	file.Metadata.Set("desktop_backend_compat_id", "compat-123")
	file.Metadata.Unset("desktop_unused")

	if err := file.Write(path); err != nil {
		t.Fatalf("Write(VERSION): %v", err)
	}

	gotBytes, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile(VERSION): %v", err)
	}
	got := string(gotBytes)
	for _, needle := range []string{
		"1.0.1\nstable\n0\n",
		"desktop_backend_change_scope=bindings",
		"desktop_release_mode=codepush",
		"desktop_binary_version_min=1.0.0",
		"desktop_binary_version_max=1.0.1",
		"desktop_backend_compat_id=compat-123",
	} {
		if !strings.Contains(got, needle) {
			t.Fatalf("VERSION missing %q:\n%s", needle, got)
		}
	}
	if strings.Contains(got, "desktop_unused=temporary") {
		t.Fatalf("VERSION still contains removed metadata:\n%s", got)
	}
}

func TestRunnerExecutesReleaseFlow(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	remote := filepath.Join(t.TempDir(), "remote.git")
	mustRun(t, root, "git", "init")
	mustRun(t, root, "git", "config", "user.name", "Release Test")
	mustRun(t, root, "git", "config", "user.email", "release-test@example.com")
	mustRun(t, root, "git", "config", "commit.gpgsign", "false")
	mustRun(t, root, "git", "config", "tag.gpgsign", "false")
	if err := os.WriteFile(filepath.Join(root, "flake.nix"), []byte("{ outputs = { self }: {}; }\n"), 0o644); err != nil {
		t.Fatalf("WriteFile(flake.nix): %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "VERSION"), []byte("1.0.0\nstable\n0\ndesktop_backend_change_scope=bindings\ndesktop_release_mode=binary\ndesktop_unused=temporary\n"), 0o644); err != nil {
		t.Fatalf("WriteFile(VERSION): %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "notes.txt"), []byte("version=old\n"), 0o644); err != nil {
		t.Fatalf("WriteFile(notes.txt): %v", err)
	}
	mustRun(t, root, "git", "add", "-A")
	mustRun(t, root, "git", "commit", "-m", "init")
	mustRun(t, root, "git", "init", "--bare", remote)
	mustRun(t, root, "git", "remote", "add", "origin", remote)
	mustRun(t, root, "git", "push", "-u", "origin", "HEAD")

	binDir := t.TempDir()
	if err := os.MkdirAll(binDir, 0o755); err != nil {
		t.Fatalf("MkdirAll(bin): %v", err)
	}
	nixPath := filepath.Join(binDir, "nix")
	nixScript := "#!/usr/bin/env bash\nif [[ \"${1-}\" == \"fmt\" ]]; then\n  exit 0\nfi\necho \"unexpected nix invocation: $*\" >&2\nexit 1\n"
	if err := os.WriteFile(nixPath, []byte(nixScript), 0o755); err != nil {
		t.Fatalf("WriteFile(bin/nix): %v", err)
	}

	r := &Runner{
		Config: Config{
			RootDir:         root,
			AllowedChannels: []string{"alpha", "beta", "rc", "internal"},
			ReleaseStepsJSON: mustJSON(t, []ReleaseStep{
				{Kind: "writeFile", Path: "generated/version.txt", Text: "$FULL_VERSION\n"},
				{Kind: "replace", Path: "notes.txt", Regex: "^version=.*$", Replacement: "version=$FULL_VERSION"},
				{Kind: "writeFile", Path: "release.tag", Text: "$FULL_TAG\n"},
				{Kind: "writeFile", Path: "metadata/scope.txt", Text: "$VERSION_META_DESKTOP_BACKEND_CHANGE_SCOPE\n"},
				{Kind: "writeFile", Path: "metadata/mode-before.txt", Text: "$VERSION_META_DESKTOP_RELEASE_MODE\n"},
				{Kind: "versionMetaSet", Key: "desktop_release_mode", Value: "codepush"},
				{Kind: "versionMetaSet", Key: "desktop_binary_version_min", Value: "1.0.0"},
				{Kind: "versionMetaSet", Key: "desktop_binary_version_max", Value: "$FULL_VERSION"},
				{Kind: "versionMetaSet", Key: "desktop_backend_compat_id", Value: "compat-123"},
				{Kind: "versionMetaUnset", Key: "desktop_unused"},
			}),
			PostVersion: "printf '%s\\n' \"$FULL_VERSION\" >\"$ROOT_DIR/post-version.txt\"",
			Execution: ExecutionOptions{
				Commit: true,
				Tag:    true,
				Push:   true,
			},
			Env: append(os.Environ(), "PATH="+binDir+string(os.PathListSeparator)+os.Getenv("PATH")),
		},
	}

	if err := r.Run([]string{"patch"}); err != nil {
		t.Fatalf("Runner.Run: %v", err)
	}

	versionFile, err := ReadVersionFile(filepath.Join(root, "VERSION"))
	if err != nil {
		t.Fatalf("ReadVersionFile(after): %v", err)
	}
	if got := versionFile.Current().String(); got != "1.0.1" {
		t.Fatalf("Current() after release = %q, want 1.0.1", got)
	}

	assertFileEquals(t, filepath.Join(root, "generated/version.txt"), "1.0.1\n")
	assertFileEquals(t, filepath.Join(root, "notes.txt"), "version=1.0.1\n")
	assertFileEquals(t, filepath.Join(root, "release.tag"), "v1.0.1\n")
	assertFileEquals(t, filepath.Join(root, "metadata/scope.txt"), "bindings\n")
	assertFileEquals(t, filepath.Join(root, "metadata/mode-before.txt"), "binary\n")
	assertFileEquals(t, filepath.Join(root, "post-version.txt"), "1.0.1\n")

	versionBytes, err := os.ReadFile(filepath.Join(root, "VERSION"))
	if err != nil {
		t.Fatalf("ReadFile(VERSION after): %v", err)
	}
	versionText := string(versionBytes)
	for _, needle := range []string{
		"desktop_backend_change_scope=bindings",
		"desktop_release_mode=codepush",
		"desktop_binary_version_min=1.0.0",
		"desktop_binary_version_max=1.0.1",
		"desktop_backend_compat_id=compat-123",
	} {
		if !strings.Contains(versionText, needle) {
			t.Fatalf("VERSION missing %q:\n%s", needle, versionText)
		}
	}
	if strings.Contains(versionText, "desktop_unused=temporary") {
		t.Fatalf("VERSION still contains removed metadata:\n%s", versionText)
	}

	tagList := strings.TrimSpace(mustOutput(t, root, "git", "tag", "--list", "v1.0.1"))
	if tagList != "v1.0.1" {
		t.Fatalf("git tag --list v1.0.1 = %q, want v1.0.1", tagList)
	}
}

func TestRunnerLeavesChangesUncommittedByDefault(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	mustRun(t, root, "git", "init")
	mustRun(t, root, "git", "config", "user.name", "Release Test")
	mustRun(t, root, "git", "config", "user.email", "release-test@example.com")
	if err := os.WriteFile(filepath.Join(root, "flake.nix"), []byte("{ outputs = { self }: {}; }\n"), 0o644); err != nil {
		t.Fatalf("WriteFile(flake.nix): %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "VERSION"), []byte("1.0.0\nstable\n0\n"), 0o644); err != nil {
		t.Fatalf("WriteFile(VERSION): %v", err)
	}
	mustRun(t, root, "git", "add", "-A")
	mustRun(t, root, "git", "commit", "-m", "init")

	binDir := t.TempDir()
	if err := os.MkdirAll(binDir, 0o755); err != nil {
		t.Fatalf("MkdirAll(bin): %v", err)
	}
	nixPath := filepath.Join(binDir, "nix")
	nixScript := "#!/usr/bin/env bash\nif [[ \"${1-}\" == \"fmt\" ]]; then\n  exit 0\nfi\necho \"unexpected nix invocation: $*\" >&2\nexit 1\n"
	if err := os.WriteFile(nixPath, []byte(nixScript), 0o755); err != nil {
		t.Fatalf("WriteFile(bin/nix): %v", err)
	}

	r := &Runner{
		Config: Config{
			RootDir:         root,
			AllowedChannels: []string{"alpha", "beta", "rc", "internal"},
			Env:             append(os.Environ(), "PATH="+binDir+string(os.PathListSeparator)+os.Getenv("PATH")),
		},
	}

	if err := r.Run([]string{"patch"}); err != nil {
		t.Fatalf("Runner.Run: %v", err)
	}

	assertFileEquals(t, filepath.Join(root, "VERSION"), "1.0.1\nstable\n0\n")
	status := strings.TrimSpace(mustOutput(t, root, "git", "status", "--short"))
	if status != "M VERSION" {
		t.Fatalf("git status --short = %q, want %q", status, "M VERSION")
	}

	tagList := strings.TrimSpace(mustOutput(t, root, "git", "tag", "--list"))
	if tagList != "" {
		t.Fatalf("git tag --list = %q, want empty", tagList)
	}
}

func TestRunnerDryRunDoesNotModifyRepo(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	mustRun(t, root, "git", "init")
	mustRun(t, root, "git", "config", "user.name", "Release Test")
	mustRun(t, root, "git", "config", "user.email", "release-test@example.com")
	if err := os.WriteFile(filepath.Join(root, "flake.nix"), []byte("{ outputs = { self }: {}; }\n"), 0o644); err != nil {
		t.Fatalf("WriteFile(flake.nix): %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "VERSION"), []byte("1.0.0\nstable\n0\n"), 0o644); err != nil {
		t.Fatalf("WriteFile(VERSION): %v", err)
	}
	mustRun(t, root, "git", "add", "-A")
	mustRun(t, root, "git", "commit", "-m", "init")

	var stdout strings.Builder
	r := &Runner{
		Config: Config{
			RootDir:         root,
			AllowedChannels: []string{"alpha", "beta", "rc", "internal"},
			Execution: ExecutionOptions{
				DryRun: true,
				Commit: true,
				Tag:    true,
				Push:   true,
			},
			Stdout: &stdout,
		},
	}

	if err := r.Run([]string{"patch"}); err != nil {
		t.Fatalf("Runner.Run: %v", err)
	}

	assertFileEquals(t, filepath.Join(root, "VERSION"), "1.0.0\nstable\n0\n")
	status := strings.TrimSpace(mustOutput(t, root, "git", "status", "--short"))
	if status != "" {
		t.Fatalf("git status --short = %q, want empty", status)
	}
	if !strings.Contains(stdout.String(), "Dry run: 1.0.1") {
		t.Fatalf("dry-run output missing next version:\n%s", stdout.String())
	}
}

func MustParseVersion(t *testing.T, raw string) Version {
	t.Helper()
	v, err := ParseVersion(raw)
	if err != nil {
		t.Fatalf("ParseVersion(%q): %v", raw, err)
	}
	return v
}

func mustJSON(t *testing.T, value any) string {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatalf("json.Marshal: %v", err)
	}
	return string(data)
}

func mustRun(t *testing.T, dir string, name string, args ...string) {
	t.Helper()
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Env = os.Environ()
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%s %s failed: %v\n%s", name, strings.Join(args, " "), err, string(out))
	}
}

func mustOutput(t *testing.T, dir string, name string, args ...string) string {
	t.Helper()
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Env = os.Environ()
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%s %s failed: %v\n%s", name, strings.Join(args, " "), err, string(out))
	}
	return string(out)
}

func assertFileEquals(t *testing.T, path string, want string) {
	t.Helper()
	gotBytes, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile(%s): %v", path, err)
	}
	if got := string(gotBytes); got != want {
		t.Fatalf("%s = %q, want %q", path, got, want)
	}
}
