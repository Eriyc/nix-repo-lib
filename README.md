# repo-lib

`repo-lib` is a pure-first Nix flake library for repo-level developer workflows:

- `mkRepo` for `devShells`, `checks`, `formatter`, and optional `packages.release`
- structured tool banners driven from package-backed tool specs
- structured release steps (`writeFile`, `replace`, `versionMetaSet`, `versionMetaUnset`)
- a Bun-only Moonrepo + TypeScript + Varlock template in [`template/`](/Users/eric/Projects/repo-lib/template)

Audit and replacement review: [`docs/reviews/2026-03-21-repo-lib-audit.md`](/Users/eric/Projects/repo-lib/docs/reviews/2026-03-21-repo-lib-audit.md)

## Prerequisites

- [Nix](https://nixos.org/download/) with flakes enabled
- [`direnv`](https://direnv.net/) (recommended)

## Use the template

```bash
nix flake new myapp -t 'git+https://git.dgren.dev/eric/nix-flake-lib?ref=refs/tags/v3.6.0#default' --refresh
```

The generated repo includes:

- a `repo-lib`-managed Nix flake
- Bun as the only JS runtime and package manager
- Moonrepo root tasks
- shared TypeScript configs adapted from `../moon`
- Varlock with a committed `.env.schema`
- empty `apps/` and `packages/` directories for new projects

## Use the library

Add this flake input:

```nix
inputs.repo-lib.url = "git+https://git.dgren.dev/eric/nix-flake-lib?ref=refs/tags/v3.6.0";
inputs.repo-lib.inputs.nixpkgs.follows = "nixpkgs";
```

Build your repo outputs from `mkRepo`:

```nix
outputs = { self, nixpkgs, repo-lib, ... }:
  repo-lib.lib.mkRepo {
    inherit self nixpkgs;
    src = ./.;

    config = {
      checks.tests = {
        command = "echo 'No tests defined yet.'";
        stage = "pre-push";
        passFilenames = false;
      };

      release = {
        steps = [ ];
      };
    };

    perSystem = { pkgs, system, ... }: {
      tools = [
        (repo-lib.lib.tools.fromCommand {
          name = "Nix";
          version.args = [ "--version" ];
          command = "nix";
        })
      ];

      shell.packages = [
        self.packages.${system}.release
      ];
    };
  };
```

`mkRepo` generates:

- `devShells.${system}.default`
- `checks.${system}.hook-check`
- `checks.${system}.lefthook-check`
- `formatter.${system}`
- `packages.${system}.release` when `config.release != null`
- merged `packages` and `apps` from `perSystem`

Checks are installed through `lefthook`, with `pre-commit` and `pre-push` commands configured to run in parallel.
repo-lib also sets Lefthook `output = [ "failure" "summary" ]` by default.

For advanced Lefthook features, use raw `config.lefthook` or `perSystem.lefthook`. Those attrsets are merged after generated checks, so you can augment a generated command with fields that the simple `checks` abstraction does not carry, such as `stage_fixed`:

```nix
config.lefthook.pre-push.commands.tests.stage_fixed = true;
```

## Tool banners

Tools are declared once. Package-backed tools are added to the shell automatically, and both package-backed and command-backed tools are rendered in the startup banner.

```nix
(repo-lib.lib.tools.fromPackage {
  name = "Go";
  package = pkgs.go;
  version.args = [ "version" ];
  banner.color = "CYAN";
})
```

Required tools fail shell startup if their version probe fails. This keeps banner output honest instead of silently hiding misconfiguration.

When a tool should come from the host environment instead of `nixpkgs`, use `fromCommand`:

```nix
(repo-lib.lib.tools.fromCommand {
  name = "Nix";
  command = "nix";
  version.args = [ "--version" ];
})
```

## Purity model

The default path is pure: declare tools and packages in Nix, then let `mkRepo` assemble the shell.

Impure bootstrap work is still possible, but it must be explicit:

```nix
config.shell = {
  bootstrap = ''
    export GOBIN="$PWD/.tools/bin"
    export PATH="$GOBIN:$PATH"
  '';
  allowImpureBootstrap = true;
};
```

## Release steps

Structured release steps are preferred over raw `sed` snippets:

```nix
config.release = {
  steps = [
    {
      writeFile = {
        path = "src/version.ts";
        text = ''
          export const APP_VERSION = "$FULL_VERSION" as const;
        '';
      };
    }
    {
      replace = {
        path = "README.md";
        regex = ''^(version = ")[^"]*(")$'';
        replacement = ''\1$FULL_VERSION\2'';
      };
    }
    {
      versionMetaSet = {
        key = "desktop_binary_version_max";
        value = "$FULL_VERSION";
      };
    }
  ];
};
```

The generated `release` command still supports:

```bash
release
release select
release --dry-run patch
release patch
release patch --commit
release patch --commit --tag
release patch --commit --tag --push
release beta
release minor beta
release stable
release set 1.2.3
```

By default, `release` updates repo files, runs structured release steps, executes `postVersion`, and runs `nix fmt`, but it does not commit, tag, or push unless you opt in with flags.

- `--commit` stages all changes and creates `chore(release): <tag>`
- `--tag` creates the Git tag after commit
- `--push` pushes the current branch and, when tagging is enabled, pushes tags too
- `--dry-run` resolves and prints the plan without mutating the repo

When `release` runs with no args in an interactive terminal, it opens a Bubble Tea picker so you can preview the exact command, flags, and resolved next version before executing it. Use `release select` to force that picker explicitly.

## Low-level APIs

`mkRelease` remains available for repos that want lower-level control over release automation.

## Common command

```bash
nix fmt
```
