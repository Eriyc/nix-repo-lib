package release

import (
	"fmt"
	"io"
)

func (r *Runner) runReleaseSteps(rootDir string, versionPath string, versionFile *VersionFile, version Version, stdout io.Writer, stderr io.Writer) error {
	steps, err := decodeReleaseSteps(r.Config.ReleaseStepsJSON)
	if err != nil {
		return err
	}
	if len(steps) == 0 {
		return nil
	}

	ctx := newReleaseStepContext(rootDir, versionPath, versionFile, version, r.Config.Env)
	for i, step := range steps {
		if err := applyReleaseStep(ctx, step); err != nil {
			return fmt.Errorf("release step %d (%s): %w", i+1, step.Kind, err)
		}
	}
	return nil
}

func applyReleaseStep(ctx *ReleaseStepContext, step ReleaseStep) error {
	switch step.Kind {
	case "writeFile":
		return applyWriteFileStep(ctx, step)
	case "replace":
		return applyReplaceStep(ctx, step)
	case "versionMetaSet":
		return applyVersionMetaSetStep(ctx, step)
	case "versionMetaUnset":
		return applyVersionMetaUnsetStep(ctx, step)
	default:
		return fmt.Errorf("unsupported release step kind %q", step.Kind)
	}
}
