package release

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

type ReleaseStepContext struct {
	RootDir     string
	VersionPath string
	Version     Version
	VersionFile *VersionFile
	Env         map[string]string
}

func newReleaseStepContext(rootDir string, versionPath string, versionFile *VersionFile, version Version, env []string) *ReleaseStepContext {
	return &ReleaseStepContext{
		RootDir:     rootDir,
		VersionPath: versionPath,
		Version:     version,
		VersionFile: versionFile,
		Env:         buildReleaseEnv(rootDir, versionFile, version, env),
	}
}

func buildReleaseEnv(rootDir string, versionFile *VersionFile, version Version, baseEnv []string) map[string]string {
	env := make(map[string]string, len(baseEnv)+8+len(versionFile.Metadata.lines))
	if len(baseEnv) == 0 {
		baseEnv = os.Environ()
	}
	for _, entry := range baseEnv {
		key, value, ok := strings.Cut(entry, "=")
		if ok {
			env[key] = value
		}
	}

	env["ROOT_DIR"] = rootDir
	env["BASE_VERSION"] = version.BaseString()
	env["CHANNEL"] = version.Channel
	env["FULL_VERSION"] = version.String()
	env["FULL_TAG"] = version.Tag()
	if version.Channel == "stable" {
		env["PRERELEASE_NUM"] = ""
	} else {
		env["PRERELEASE_NUM"] = strconv.Itoa(version.Prerelease)
	}

	for _, line := range versionFile.Metadata.lines {
		key, value, ok := strings.Cut(line, "=")
		if !ok || key == "" {
			continue
		}
		env[sanitizeMetaEnvName(key)] = value
	}
	return env
}

func (c *ReleaseStepContext) expand(raw string) string {
	return os.Expand(raw, func(name string) string {
		return c.Env[name]
	})
}

func (c *ReleaseStepContext) resolvePath(path string) string {
	expanded := c.expand(path)
	if filepath.IsAbs(expanded) {
		return expanded
	}
	return filepath.Join(c.RootDir, expanded)
}
