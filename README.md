# repo-lib

Simple Nix flake library for:

- a shared development shell (`mkDevShell`)
- an optional release command (`mkRelease`)
- a starter template (`template/`)

## Prerequisites

- [Nix](https://nixos.org/download/) with flakes enabled
- [`direnv`](https://direnv.net/) (recommended)

## Use the template (new repo)

From your new project folder:

```bash
nix flake new myapp -t 'git+https://git.dgren.dev/eric/nix-flake-lib?ref=v2.0.1#default' --refresh
```

## Use the library (existing repo)

Add this flake input:

```nix
inputs.devshell-lib.url = "git+https://git.dgren.dev/eric/nix-flake-lib?ref=v2.0.1";
inputs.devshell-lib.inputs.nixpkgs.follows = "nixpkgs";
```

Create your shell from `mkDevShell`:

```nix
env = devshell-lib.lib.mkDevShell {
  inherit system;
  src = ./.;
  extraPackages = [ ];
  preToolHook = "";
  tools = [ ];
  additionalHooks = { };
};
```

Expose it in `devShells` as `default` and run:

```bash
nix develop
```

Use `preToolHook` when a tool needs bootstrap work before the shell prints tool versions. This is useful for tools you install outside `nixpkgs`, as long as the hook is idempotent.

```nix
env = devshell-lib.lib.mkDevShell {
  inherit system;
  src = ./.;

  # assumes `go` is already available in PATH, for example via `extraPackages`

  preToolHook = ''
    export GOBIN="$PWD/.tools/bin"
    export PATH="$GOBIN:$PATH"

    if ! command -v golangci-lint >/dev/null 2>&1; then
      go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
    fi
  '';

  tools = [
    { name = "golangci-lint"; bin = "golangci-lint"; versionCmd = "version"; color = "YELLOW"; }
  ];
};
```

## Common commands

```bash
nix fmt           # format files
```

## Optional: release command

If your flake defines:

```nix
packages.${system}.release = devshell-lib.lib.mkRelease { inherit system; };
```

Run releases with:

```bash
release
release patch
release beta
release minor beta
release stable
release set 1.2.3
```

The release script uses `./VERSION` as the source of truth and creates tags like `v1.2.3`.
When switching from stable to a prerelease channel without an explicit bump (for example, `release beta`), it applies a patch bump automatically (for example, `1.0.0` -> `1.0.1-beta.1`).
