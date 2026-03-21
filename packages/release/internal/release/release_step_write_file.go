package release

import (
	"fmt"
	"os"
	"path/filepath"
)

func applyWriteFileStep(ctx *ReleaseStepContext, step ReleaseStep) error {
	targetPath := ctx.resolvePath(step.Path)
	if err := os.MkdirAll(filepath.Dir(targetPath), 0o755); err != nil {
		return fmt.Errorf("mkdir %s: %w", filepath.Dir(targetPath), err)
	}
	if err := os.WriteFile(targetPath, []byte(ctx.expand(step.Text)), 0o644); err != nil {
		return fmt.Errorf("write %s: %w", targetPath, err)
	}
	return nil
}
