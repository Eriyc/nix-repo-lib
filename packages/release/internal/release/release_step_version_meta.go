package release

import "fmt"

func applyVersionMetaSetStep(ctx *ReleaseStepContext, step ReleaseStep) error {
	ctx.VersionFile.Metadata.Set(step.Key, ctx.expand(step.Value))
	ctx.Env[sanitizeMetaEnvName(step.Key)] = ctx.VersionFile.Metadata.Get(step.Key)
	if err := ctx.VersionFile.Write(ctx.VersionPath); err != nil {
		return fmt.Errorf("write VERSION: %w", err)
	}
	return nil
}

func applyVersionMetaUnsetStep(ctx *ReleaseStepContext, step ReleaseStep) error {
	ctx.VersionFile.Metadata.Unset(step.Key)
	delete(ctx.Env, sanitizeMetaEnvName(step.Key))
	if err := ctx.VersionFile.Write(ctx.VersionPath); err != nil {
		return fmt.Errorf("write VERSION: %w", err)
	}
	return nil
}
