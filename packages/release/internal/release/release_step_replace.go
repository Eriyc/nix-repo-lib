package release

import (
	"fmt"
	"os"
	"regexp"
	"strings"
)

func applyReplaceStep(ctx *ReleaseStepContext, step ReleaseStep) error {
	targetPath := ctx.resolvePath(step.Path)
	content, err := os.ReadFile(targetPath)
	if err != nil {
		return fmt.Errorf("read %s: %w", targetPath, err)
	}

	pattern, err := regexp.Compile("(?m)" + ctx.expand(step.Regex))
	if err != nil {
		return fmt.Errorf("compile regex for %s: %w", targetPath, err)
	}

	replacement := translateReplacementBackrefs(ctx.expand(step.Replacement))
	updated := pattern.ReplaceAllString(string(content), replacement)
	if err := os.WriteFile(targetPath, []byte(updated), 0o644); err != nil {
		return fmt.Errorf("write %s: %w", targetPath, err)
	}
	return nil
}

func translateReplacementBackrefs(raw string) string {
	var b strings.Builder
	b.Grow(len(raw))

	for i := 0; i < len(raw); i++ {
		if raw[i] == '\\' && i+1 < len(raw) && raw[i+1] >= '1' && raw[i+1] <= '9' {
			b.WriteByte('$')
			b.WriteByte(raw[i+1])
			i++
			continue
		}
		b.WriteByte(raw[i])
	}
	return b.String()
}
