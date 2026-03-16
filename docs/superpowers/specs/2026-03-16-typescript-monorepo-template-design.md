# TypeScript Monorepo Template Design

## Goal

Add a new default template to this repository that generates a Bun-only TypeScript monorepo using Moonrepo, Varlock, and the shared TypeScript configuration pattern from `../moon`.

## Scope

The generated template should include:

- a Nix flake wired through `repo-lib.lib.mkRepo`
- Bun-only JavaScript tooling
- Moonrepo root configuration
- strict shared TypeScript configs adapted from `../moon`
- Varlock enabled from day one
- a committed `.env.schema`
- empty `apps/` and `packages/` directories
- minimal documentation for first-run setup

The template should not include:

- demo apps or packages
- product-specific environment variables or OpenBao paths from `../moon`
- Node or pnpm support

## Architecture

The existing `template/` directory remains the exported flake template. Instead of containing only a starter `flake.nix`, it will become a complete repository skeleton.

The generated repository will keep the current `repo-lib` integration pattern:

- `template/flake.nix` calls `repo-lib.lib.mkRepo`
- the shell provisions Bun, Moonrepo CLI, Varlock, and supporting tooling
- repo checks remain driven through `mkRepo` and Lefthook

Moonrepo and Varlock will be configured at the workspace root. The template will expose root tasks and scripts that work even before any projects are added.

## Template Contents

The template should contain:

- `flake.nix`
- `package.json`
- `bunfig.toml`
- `moon.yml`
- `tsconfig.json`
- `tsconfig.options.json`
- `tsconfig/browser.json`
- `tsconfig/bun.json`
- `tsconfig/package.json`
- `tsconfig/runtime.json`
- `.env.schema`
- `.gitignore`
- `README.md`
- `apps/.gitkeep`
- `packages/.gitkeep`

It may also keep generic repo support files already useful in templates, such as `.envrc`, `.gitlint`, `.gitleaks.toml`, `.vscode/settings.json`, and `flake.lock`, as long as they remain template-safe.

## Data And Command Flow

On first use:

1. the user creates a repo from the flake template
2. the shell provides Bun, Moonrepo, Varlock, and release support
3. `bun install` installs `@moonrepo/cli`, `varlock`, and TypeScript-related dependencies
4. entering the repo loads `varlock/auto-load`
5. root commands like `bun run env:check`, `bun run env:scan`, and `moon run :typecheck` work without any sample projects

## Varlock Design

The template will include a minimal `.env.schema` with:

- one canonical environment selector
- safe local defaults where practical
- placeholders for OpenBao-backed secrets using generic template paths

Root scripts in `package.json` will follow the `../moon` pattern for `env:check` and `env:scan`, including `BAO_*` and `OPENBAO_*` compatibility exports. The template will not encode any product-specific namespace names.

## Testing

Existing release tests must continue to validate the exported template. The template fixture helper in `tests/release.sh` will need to copy the full template directory, not only `template/flake.nix`, so `nix flake show` exercises the real generated repository structure.

## Risks

- Moonrepo root task behavior must remain valid with no projects present.
- Template-safe Varlock defaults must avoid broken first-run behavior while still demonstrating the intended pattern.
- The release test harness must not accidentally preserve upstream URLs inside the copied template.
