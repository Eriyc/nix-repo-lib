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
nix flake new myapp -t 'git+https://git.dgren.dev/eric/nix-flake-lib.git?ref=v1.0.0#default' --refresh
```

## Use the library (existing repo)

Add this flake input:

```nix
inputs.devshell-lib.url = "git+https://git.dgren.dev/eric/nix-flake-lib?ref=v1.0.0";
inputs.devshell-lib.inputs.nixpkgs.follows = "nixpkgs";
```

Create your shell from `mkDevShell`:

```nix
env = devshell-lib.lib.mkDevShell {
  inherit system;
  extraPackages = [ ];
  tools = [ ];
  additionalHooks = { };
};
```

Expose it in `devShells` as `default` and run:

```bash
nix develop
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
release minor beta
release stable
release set 1.2.3
```

The release script uses `./VERSION` as the source of truth and creates tags like `v1.2.3`.
