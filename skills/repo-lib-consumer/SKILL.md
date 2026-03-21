---
name: repo-lib-consumer
description: Edit or extend repos that consume `repo-lib` through `repo-lib.lib.mkRepo`, `repo-lib.lib.mkRelease`, or a template generated from this library. Use when Codex needs to add or change tools, shell banner or bootstrap behavior, shell packages, checks, raw lefthook config, formatters, release steps, version metadata, release channels, or release automation in a Nix flake built on repo-lib.
---

# Repo Lib Consumer

Use this skill when changing a repo that already depends on `repo-lib`.

## Workflow

1. Detect the integration style.
   Search for `repo-lib.lib.mkRepo`, `repo-lib.lib.mkRelease`, or `inputs.repo-lib`.

2. Prefer the repo's current abstraction level.
   If the repo uses `mkRepo`, keep edits inside `config` and `perSystem`.
   If the repo uses `mkRelease` directly, preserve that style unless the user asked to migrate.

3. Load the right reference before editing.
   Read `references/api.md` for exact option names, merge points, generated outputs, hook limitations, and release behavior.
   Read `references/recipes.md` for concrete change patterns such as adding a tool, adding a check, wiring `commit-msg`, changing the banner, or updating release-managed files.

4. Follow repo-lib conventions.
   Add bannered CLIs through `perSystem.tools`, not `shell.packages`.
   Use `shell.packages` for packages that should exist in the shell but not in the banner.
   Keep shells pure-first; only use `bootstrap` with `allowImpureBootstrap = true`.
   Prefer `config.checks` for simple `pre-commit` and `pre-push` commands.
   Use raw `config.lefthook` or `perSystem.lefthook` when the task needs `commit-msg` or extra lefthook fields.
   Prefer structured `release.steps` over shell hooks; current step kinds are `writeFile`, `replace`, `versionMetaSet`, and `versionMetaUnset`.

5. Verify after edits.
   Run `nix flake show --json`.
   Run `nix flake check` when feasible.
   If local flake evaluation cannot see newly created files because the repo is loaded as a git flake, stage the new files before rerunning checks.

## Decision Rules

- Prefer `repo-lib.lib.tools.fromPackage` for packaged CLIs and `fromCommand` only when the tool should come from the host environment.
- Use `repo-lib.lib.tools.simple` only for very small package-backed probes that only need `version.args`.
- Required tools fail shell startup if their probe fails. Do not mark a tool optional unless that is intentional.
- `config.checks` supports only `pre-commit` and `pre-push`. `commit-msg` must go through raw lefthook config.
- Generated checks include `formatting-check`, `hook-check`, and `lefthook-check`.
- `config.shell.banner.style` must be `simple` or `pretty`.
- Treat `postVersion` as pre-format, pre-commit, pre-tag, and pre-push.
- Do not model a true post-tag webhook inside `repo-lib`; prefer CI triggered by tag push.
- The current generated `release` command is destructive and opinionated: it formats, stages, commits, tags, and pushes as part of the flow. Document that clearly when editing consumer release automation.

## References

- `references/api.md`
  Use for the exact consumer API, generated outputs, hook and banner behavior, and current release semantics.

- `references/recipes.md`
  Use for common changes: add a tool, add a check, add a `commit-msg` hook, customize the shell banner, or update release-managed files.
