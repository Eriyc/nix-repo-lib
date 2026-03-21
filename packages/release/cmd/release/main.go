package main

import (
	"fmt"
	"os"
	"strings"

	release "repo-lib/packages/release/internal/release"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) > 0 && args[0] == "version-meta" {
		return runVersionMeta(args[1:])
	}

	releaseArgs, execution, selectMode, err := parseReleaseCLIArgs(args)
	if err != nil {
		return err
	}

	config := release.Config{
		RootDir:          os.Getenv("REPO_LIB_RELEASE_ROOT_DIR"),
		AllowedChannels:  splitEnvList("REPO_LIB_RELEASE_CHANNELS"),
		ReleaseStepsJSON: os.Getenv("REPO_LIB_RELEASE_STEPS_JSON"),
		PostVersion:      os.Getenv("REPO_LIB_RELEASE_POST_VERSION"),
		Execution:        execution,
		Env:              os.Environ(),
		Stdout:           os.Stdout,
		Stderr:           os.Stderr,
	}

	if shouldRunInteractiveSelector(releaseArgs, selectMode) {
		if !release.IsInteractiveTerminal(os.Stdin, os.Stdout) {
			return fmt.Errorf("interactive release selector requires a terminal")
		}
		selectedArgs, confirmed, err := release.SelectCommand(config)
		if err != nil {
			return err
		}
		if !confirmed {
			return nil
		}
		releaseArgs = selectedArgs
	}

	r := &release.Runner{Config: config}
	return r.Run(releaseArgs)
}

func shouldRunInteractiveSelector(args []string, selectMode bool) bool {
	if selectMode {
		return true
	}
	if len(args) == 0 {
		return release.IsInteractiveTerminal(os.Stdin, os.Stdout)
	}
	return false
}

func parseReleaseCLIArgs(args []string) ([]string, release.ExecutionOptions, bool, error) {
	var releaseArgs []string
	execution := release.ExecutionOptions{}
	selectMode := false

	for _, arg := range args {
		switch arg {
		case "select":
			selectMode = true
		default:
			if strings.HasPrefix(arg, "--") {
				return nil, release.ExecutionOptions{}, false, fmt.Errorf("unknown flag %q", arg)
			}
			releaseArgs = append(releaseArgs, arg)
		}
	}

	if selectMode && len(releaseArgs) > 0 {
		return nil, release.ExecutionOptions{}, false, fmt.Errorf("select does not take a release argument")
	}
	return releaseArgs, execution.Normalize(), selectMode, nil
}

func runVersionMeta(args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("version-meta requires an action and key")
	}
	rootDir := os.Getenv("ROOT_DIR")
	if rootDir == "" {
		return fmt.Errorf("ROOT_DIR is required")
	}
	versionPath := rootDir + "/VERSION"
	file, err := release.ReadVersionFile(versionPath)
	if err != nil {
		return err
	}

	switch args[0] {
	case "set":
		if len(args) != 3 {
			return fmt.Errorf("version-meta set requires key and value")
		}
		file.Metadata.Set(args[1], args[2])
	case "unset":
		if len(args) != 2 {
			return fmt.Errorf("version-meta unset requires key")
		}
		file.Metadata.Unset(args[1])
	default:
		return fmt.Errorf("unknown version-meta action %q", args[0])
	}
	return file.Write(versionPath)
}

func splitEnvList(name string) []string {
	raw := strings.Fields(os.Getenv(name))
	if len(raw) == 0 {
		return nil
	}
	return raw
}
