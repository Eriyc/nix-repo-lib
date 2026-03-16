# TypeScript Monorepo Template

This template gives you a Bun-only monorepo with:

- Moonrepo at the workspace root
- strict shared TypeScript configs
- Varlock with a committed `.env.schema`
- a Nix flake shell built through `repo-lib`

## First Run

1. Enter the shell with `direnv allow` or `nix develop`.
2. Install workspace dependencies with `bun install`.
3. Review and customize `.env.schema` for your repo.
4. Run `bun run env:check`.
5. Run `moon run :typecheck`.

## Layout

- `apps/` for applications
- `packages/` for shared libraries
- `tsconfig/` for shared TypeScript profiles
- `moon.yml` for root Moonrepo tasks

## Varlock

`bunfig.toml` preloads `varlock/auto-load`, and the root scripts expose:

- `bun run env:check`
- `bun run env:scan`

If you use OpenBao locally, set `OPENBAO_ADDR`, `OPENBAO_NAMESPACE`, and `OPENBAO_CACERT` in your shell or an ignored `.env.sh` file before running those commands.
