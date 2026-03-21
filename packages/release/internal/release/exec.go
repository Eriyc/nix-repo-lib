package release

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func requireCleanGit(rootDir string) error {
	if _, err := runCommand(rootDir, nil, io.Discard, io.Discard, "git", "diff", "--quiet"); err != nil {
		return errors.New("git working tree is not clean. Commit or stash changes first")
	}
	if _, err := runCommand(rootDir, nil, io.Discard, io.Discard, "git", "diff", "--cached", "--quiet"); err != nil {
		return errors.New("git working tree is not clean. Commit or stash changes first")
	}
	return nil
}

func gitOutput(dir string, args ...string) (string, error) {
	return runCommand(dir, nil, nil, nil, "git", args...)
}

func runCommand(dir string, env []string, stdout io.Writer, stderr io.Writer, name string, args ...string) (string, error) {
	resolvedName, err := resolveExecutable(name, env)
	if err != nil {
		return "", err
	}
	cmd := exec.Command(resolvedName, args...)
	if dir != "" {
		cmd.Dir = dir
	}
	if env != nil {
		cmd.Env = env
	} else {
		cmd.Env = os.Environ()
	}

	var out bytes.Buffer
	cmd.Stdout = io.MultiWriter(&out, writerOrDiscard(stdout))
	cmd.Stderr = io.MultiWriter(&out, writerOrDiscard(stderr))
	err = cmd.Run()
	if err != nil {
		output := strings.TrimSpace(out.String())
		if output == "" {
			return out.String(), fmt.Errorf("%s %s: %w", name, strings.Join(args, " "), err)
		}
		return out.String(), fmt.Errorf("%s %s: %w\n%s", name, strings.Join(args, " "), err, output)
	}
	return out.String(), nil
}

func resolveExecutable(name string, env []string) (string, error) {
	if strings.ContainsRune(name, os.PathSeparator) {
		return name, nil
	}

	pathValue := os.Getenv("PATH")
	for _, entry := range env {
		if strings.HasPrefix(entry, "PATH=") {
			pathValue = strings.TrimPrefix(entry, "PATH=")
		}
	}

	for _, dir := range filepath.SplitList(pathValue) {
		if dir == "" {
			dir = "."
		}
		candidate := filepath.Join(dir, name)
		info, err := os.Stat(candidate)
		if err != nil || info.IsDir() {
			continue
		}
		if info.Mode()&0o111 == 0 {
			continue
		}
		return candidate, nil
	}
	return "", fmt.Errorf("executable %q not found in PATH", name)
}

func writerOrDiscard(w io.Writer) io.Writer {
	if w == nil {
		return io.Discard
	}
	return w
}
