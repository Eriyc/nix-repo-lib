---
name: repo-lib-consumer
description: Edit or extend repos that consume `repo-lib` through `repo-lib.lib.mkRepo`, `mkDevShell`, or `mkRelease`. Use when Codex needs to add or change tools, shell packages, checks or test phases, formatters, release steps, release channels, bootstrap hooks, or release automation in a Nix flake built on repo-lib.
---

# Repo Lib Consumer

Use this skill to make idiomatic changes in a repo that already depends on `repo-lib`.

## Workflow

1. Detect the integration style.
   Search for `repo-lib.lib.mkRepo`, `repo-lib.lib.mkDevShell`, `repo-lib.lib.mkRelease`, or `inputs.repo-lib`.

2. Prefer the repo's current abstraction level.
   If the repo already uses `mkRepo`, stay on `mkRepo`.
   If the repo still uses `mkDevShell` or `mkRelease`, preserve that style unless the user asked to migrate.

3. Load the right reference before editing.
   Read `references/api.md` for exact option names, defaults, generated outputs, and limitations.
   Read `references/recipes.md` for common edits such as adding a tool, adding a test phase, wiring release file updates, or handling webhooks.

4. Follow repo-lib conventions.
   Add bannered CLIs through `perSystem.tools`, not `shell.packages`.
   Use `shell.packages` for packages that should be present in the shell but not shown in the banner.
   Keep shells pure-first; only use `bootstrap` with `allowImpureBootstrap = true`.
   Prefer structured `release.steps` over free-form shell when the task fits `writeFile` or `replace`.

5. Verify after edits.
   Run `nix flake show --json`.
   Run `nix flake check` when feasible.
   If local flake evaluation cannot see newly created files because the repo is being loaded as a git flake, stage the new files before rerunning checks.

## Decision Rules

- Prefer `repo-lib.lib.tools.fromPackage` for tools with explicit metadata.
- Use `repo-lib.lib.tools.simple` only for very simple `--version` or `version` probes.
- Put pre-commit and pre-push automation in `checks`, not shell hooks.
- Treat `postVersion` as pre-tag and pre-push. It is not a true post-tag hook.
- For a webhook that must fire after the tag exists remotely, prefer CI triggered by tag push over local release command changes.

## References

- `references/api.md`
  Use for the exact consumer API, option matrix, generated outputs, release ordering, and legacy compatibility.

- `references/recipes.md`
  Use for concrete change patterns: add a tool, add a test phase, update release-managed files, or wire webhook behavior.
