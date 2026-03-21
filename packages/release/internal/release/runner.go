package release

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

type Config struct {
	RootDir          string
	AllowedChannels  []string
	ReleaseStepsJSON string
	PostVersion      string
	Execution        ExecutionOptions
	Env              []string
	Stdout           io.Writer
	Stderr           io.Writer
}

type ExecutionOptions struct {
	DryRun bool
	Commit bool
	Tag    bool
	Push   bool
}

type Runner struct {
	Config Config
}

func (o ExecutionOptions) Normalize() ExecutionOptions {
	if o.Push {
		o.Commit = true
	}
	if o.Tag {
		o.Commit = true
	}
	return o
}

func (r *Runner) Run(args []string) error {
	rootDir, err := r.rootDir()
	if err != nil {
		return err
	}

	stdout := writerOrDiscard(r.Config.Stdout)
	stderr := writerOrDiscard(r.Config.Stderr)
	execution := r.Config.Execution.Normalize()

	versionFile, versionPath, err := r.loadVersionFile(rootDir)
	if err != nil {
		return err
	}

	nextVersion, err := ResolveNextVersion(versionFile.Version, args, r.Config.AllowedChannels)
	if err != nil {
		return err
	}

	if execution.DryRun {
		printReleasePlan(stdout, nextVersion, execution, strings.TrimSpace(r.Config.ReleaseStepsJSON) != "", strings.TrimSpace(r.Config.PostVersion) != "")
		return nil
	}

	if err := requireCleanGit(rootDir); err != nil {
		return err
	}

	versionFile.Version = nextVersion
	if err := versionFile.Write(versionPath); err != nil {
		return err
	}
	if err := r.runReleaseSteps(rootDir, versionPath, versionFile, nextVersion, stdout, stderr); err != nil {
		return err
	}
	if err := r.runShell(rootDir, versionFile, nextVersion, r.Config.PostVersion, stdout, stderr); err != nil {
		return err
	}

	if err := r.finalizeRelease(rootDir, nextVersion, execution, stdout, stderr); err != nil {
		return err
	}
	return nil
}

func (r *Runner) rootDir() (string, error) {
	if r.Config.RootDir != "" {
		return r.Config.RootDir, nil
	}
	rootDir, err := gitOutput("", "rev-parse", "--show-toplevel")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(rootDir), nil
}

func (r *Runner) loadVersionFile(rootDir string) (*VersionFile, string, error) {
	versionPath := filepath.Join(rootDir, "VERSION")
	if _, err := os.Stat(versionPath); err != nil {
		return nil, "", fmt.Errorf("VERSION file not found at %s", versionPath)
	}
	versionFile, err := ReadVersionFile(versionPath)
	if err != nil {
		return nil, "", err
	}
	return versionFile, versionPath, nil
}

func (r *Runner) finalizeRelease(rootDir string, version Version, execution ExecutionOptions, stdout io.Writer, stderr io.Writer) error {
	if _, err := runCommand(rootDir, r.Config.Env, stdout, stderr, "nix", "fmt"); err != nil {
		return err
	}

	if !execution.Commit {
		return nil
	}

	if _, err := runCommand(rootDir, r.Config.Env, stdout, stderr, "git", "add", "-A"); err != nil {
		return err
	}

	commitMsg := "chore(release): " + version.Tag()
	if _, err := runCommand(rootDir, r.Config.Env, stdout, stderr, "git", "commit", "-m", commitMsg); err != nil {
		return err
	}

	if execution.Tag {
		if _, err := runCommand(rootDir, r.Config.Env, stdout, stderr, "git", "tag", version.Tag()); err != nil {
			return err
		}
	}

	if !execution.Push {
		return nil
	}

	if _, err := runCommand(rootDir, r.Config.Env, stdout, stderr, "git", "push"); err != nil {
		return err
	}
	if execution.Tag {
		if _, err := runCommand(rootDir, r.Config.Env, stdout, stderr, "git", "push", "--tags"); err != nil {
			return err
		}
	}
	return nil
}

func printReleasePlan(stdout io.Writer, version Version, execution ExecutionOptions, hasReleaseSteps bool, hasPostVersion bool) {
	fmt.Fprintf(stdout, "Dry run: %s\n", version.String())
	fmt.Fprintf(stdout, "Tag: %s\n", version.Tag())
	fmt.Fprintf(stdout, "Release steps: %s\n", yesNo(hasReleaseSteps))
	fmt.Fprintf(stdout, "Post-version: %s\n", yesNo(hasPostVersion))
	fmt.Fprintf(stdout, "nix fmt: yes\n")
	fmt.Fprintf(stdout, "git commit: %s\n", yesNo(execution.Commit))
	fmt.Fprintf(stdout, "git tag: %s\n", yesNo(execution.Tag))
	fmt.Fprintf(stdout, "git push: %s\n", yesNo(execution.Push))
}
