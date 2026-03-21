package release

import (
	"bytes"
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Metadata struct {
	lines []string
}

func (m Metadata) Lines() []string {
	return append([]string(nil), m.lines...)
}

func (m Metadata) Get(key string) string {
	for _, line := range m.lines {
		if strings.HasPrefix(line, key+"=") {
			return strings.TrimPrefix(line, key+"=")
		}
	}
	return ""
}

func (m *Metadata) Set(key string, value string) {
	for i, line := range m.lines {
		if strings.HasPrefix(line, key+"=") {
			m.lines[i] = key + "=" + value
			return
		}
	}
	m.lines = append(m.lines, key+"="+value)
}

func (m *Metadata) Unset(key string) {
	filtered := make([]string, 0, len(m.lines))
	for _, line := range m.lines {
		if strings.HasPrefix(line, key+"=") {
			continue
		}
		filtered = append(filtered, line)
	}
	m.lines = filtered
}

type VersionFile struct {
	Version  Version
	Metadata Metadata
}

func (f VersionFile) Current() Version {
	return f.Version
}

func ReadVersionFile(path string) (*VersionFile, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	text := strings.ReplaceAll(string(data), "\r\n", "\n")
	lines := strings.Split(text, "\n")
	if len(lines) < 3 {
		return nil, fmt.Errorf("invalid VERSION file %q", path)
	}

	base := strings.TrimSpace(lines[0])
	channel := strings.TrimSpace(lines[1])
	preRaw := strings.TrimSpace(lines[2])
	if channel == "" {
		channel = "stable"
	}

	rawVersion := base
	if channel != "stable" {
		rawVersion = fmt.Sprintf("%s-%s.%s", base, channel, preRaw)
	}
	version, err := ParseVersion(rawVersion)
	if err != nil {
		return nil, err
	}

	metaLines := make([]string, 0, len(lines)-3)
	for _, line := range lines[3:] {
		if line == "" {
			continue
		}
		metaLines = append(metaLines, line)
	}
	return &VersionFile{
		Version:  version,
		Metadata: Metadata{lines: metaLines},
	}, nil
}

func (f *VersionFile) Write(path string) error {
	channel := f.Version.Channel
	pre := strconv.Itoa(f.Version.Prerelease)
	if channel == "" || channel == "stable" {
		channel = "stable"
		pre = "0"
	}

	var buf bytes.Buffer
	fmt.Fprintf(&buf, "%s\n%s\n%s\n", f.Version.BaseString(), channel, pre)
	for _, line := range f.Metadata.lines {
		fmt.Fprintln(&buf, line)
	}
	return os.WriteFile(path, buf.Bytes(), 0o644)
}
