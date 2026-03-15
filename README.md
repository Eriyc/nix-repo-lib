# repo-lib

`repo-lib` is a pure-first Nix flake library for repo-level developer workflows:

- `mkRepo` for `devShells`, `checks`, `formatter`, and optional `packages.release`
- structured tool banners driven from package-backed tool specs
- structured release steps (`writeFile`, `replace`, `run`)
- a minimal starter template in [`template/`](/Users/eric/Projects/repo-lib/template)

## Prerequisites

- [Nix](https://nixos.org/download/) with flakes enabled
- [`direnv`](https://direnv.net/) (recommended)

## Use the template

```bash
nix flake new myapp -t 'git+https://git.dgren.dev/eric/nix-flake-lib?ref=refs/tags/v3.1.0#default' --refresh
```

## Use the library

Add this flake input:

```nix
inputs.repo-lib.url = "git+https://git.dgren.dev/eric/nix-flake-lib?ref=refs/tags/v3.1.0";
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
- `checks.${system}.pre-commit-check`
- `formatter.${system}`
- `packages.${system}.release` when `config.release != null`
- merged `packages` and `apps` from `perSystem`

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
      run = {
        script = ''
          echo "Released $FULL_TAG"
        '';
      };
    }
  ];
};
```

The generated `release` command still supports:

```bash
release
release patch
release beta
release minor beta
release stable
release set 1.2.3
```

## Low-level APIs

`mkDevShell` and `mkRelease` remain available for repos that want lower-level control or a migration path from the older library shape.

## Common command

```bash
nix fmt
```
