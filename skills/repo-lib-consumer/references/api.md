# repo-lib Consumer API

## Detect the repo shape

Look for one of these patterns in the consuming repo:

- `repo-lib.lib.mkRepo`
- `repo-lib.lib.mkRelease`
- `inputs.repo-lib`

Prefer editing the existing style instead of migrating incidentally.

## Preferred `mkRepo` shape

```nix
repo-lib.lib.mkRepo {
  inherit self nixpkgs;
  src = ./.;
  systems = repo-lib.lib.systems.default; # optional

  config = {
    includeStandardPackages = true;

    shell = {
      env = { };
      extraShellText = "";
      allowImpureBootstrap = false;
      bootstrap = "";
      banner = { };
    };

    formatting = {
      programs = { };
      settings = { };
    };

    checks = { };
    lefthook = { };

    release = null; # or attrset below
  };

  perSystem = { pkgs, system, lib, config }: {
    tools = [ ];
    shell.packages = [ ];
    checks = { };
    lefthook = { };
    packages = { };
    apps = { };
  };
}
```

Generated outputs:

- `devShells.${system}.default`
- `checks.${system}.formatting-check`
- `checks.${system}.hook-check`
- `checks.${system}.lefthook-check`
- `formatter.${system}`
- `packages.${system}.release` when `config.release != null`
- merged `packages` and `apps` from `perSystem`

Merge points:

- `config.checks` merges with `perSystem.checks`
- `config.lefthook` recursively merges with `perSystem.lefthook`
- `config.shell` recursively merges with `perSystem.shell`
- generated release packages merge with `perSystem.packages`

Conflicts on `checks`, `packages`, and `apps` names throw.

## `config.includeStandardPackages`

Default: `true`

When enabled, the shell includes:

- `nixfmt`
- `gitlint`
- `gitleaks`
- `shfmt`

Use `false` only when the consumer explicitly wants to own the full shell package list.

## `config.shell`

Fields:

- `env`
  Attrset of environment variables exported in the shell.
- `extraShellText`
  Extra shell snippet appended after the banner.
- `bootstrap`
  Shell snippet that runs before the banner.
- `allowImpureBootstrap`
  Must be `true` when `bootstrap` is non-empty.
- `banner`
  Shell banner configuration.

Rules:

- Default is pure-first.
- Do not add bootstrap work unless the user actually wants imperative local setup.
- The template uses bootstrap intentionally for Bun global install paths and Moon bootstrapping; do not generalize that into normal package setup unless the repo already wants that behavior.

### `config.shell.banner`

Defaults:

```nix
{
  style = "simple";
  icon = "🚀";
  title = "Dev shell ready";
  titleColor = "GREEN";
  subtitle = "";
  subtitleColor = "GRAY";
  borderColor = "BLUE";
}
```

Rules:

- `style` must be `simple` or `pretty`.
- `borderColor` matters only for `pretty`.
- Tool rows can also set `banner.color`, `banner.icon`, and `banner.iconColor`.
- Required tool probe failures abort shell startup.

## `config.formatting`

Fields:

- `programs`
  Passed to `treefmt-nix.lib.evalModule`.
- `settings`
  Passed to `settings.formatter`.

Rules:

- `nixfmt` is always enabled.
- Use formatter settings instead of shell hooks for formatting behavior.

## Checks

`config.checks.<name>` and `perSystem.checks.<name>` use this shape:

```nix
{
  command = "bun test";
  stage = "pre-push"; # or "pre-commit"
  passFilenames = false;
  runtimeInputs = [ pkgs.bun ];
}
```

Defaults:

- `stage = "pre-commit"`
- `passFilenames = false`
- `runtimeInputs = [ ]`

Rules:

- Only `pre-commit` and `pre-push` are supported here.
- The command is wrapped with `writeShellApplication`.
- `pre-commit` and `pre-push` stages are configured to run in parallel.
- `passFilenames = true` maps to `{staged_files}` for `pre-commit` and `{push_files}` for `pre-push`.

## Raw Lefthook config

Use `config.lefthook` or `perSystem.lefthook` when the task needs advanced Lefthook features or unsupported stages.

Pass-through attrset example:

```nix
{
  checks.tests = {
    command = "bun test";
    stage = "pre-push";
    runtimeInputs = [ pkgs.bun ];
  };

  lefthook.pre-push.commands.tests.stage_fixed = true;

  lefthook.commit-msg.commands.commitlint = {
    run = "bun commitlint --edit {1}";
    stage_fixed = true;
  };
}
```

Structured hook-entry example in a raw hook list:

```nix
perSystem = { pkgs, ... }: {
  lefthook.biome = {
    entry = "${pkgs.biome}/bin/biome check";
    pass_filenames = true;
    stages = [ "pre-commit" "pre-push" ];
  };
};
```

Rules:

- `config.lefthook` and `perSystem.lefthook` are recursive attrset passthroughs merged after generated checks.
- Structured hook entries support only:
  `description`, `enable`, `entry`, `name`, `package`, `pass_filenames`, `stages`
- `stages` may include `pre-commit`, `pre-push`, or `commit-msg`.
- `pass_filenames = true` maps to `{1}` for `commit-msg`.

## Tools

Preferred shape in `perSystem.tools`:

```nix
(repo-lib.lib.tools.fromPackage {
  name = "Bun";
  package = pkgs.bun;
  version = {
    args = [ "--version" ];
    match = null;
    regex = null;
    group = 0;
    line = 1;
  };
  banner = {
    color = "YELLOW";
    icon = "";
    iconColor = null;
  };
  required = true;
})
```

For a tool that should come from the host `PATH` instead of `nixpkgs`:

```nix
(repo-lib.lib.tools.fromCommand {
  name = "Nix";
  command = "nix";
  version = {
    args = [ "--version" ];
    group = 1;
  };
})
```

Helper:

```nix
repo-lib.lib.tools.simple "Go" pkgs.go [ "version" ]
```

Tool behavior:

- Package-backed tools are added to the shell automatically.
- Command-backed tools are probed from the existing `PATH` and are not added to the shell automatically.
- Banner probing uses the resolved executable path.
- `required = true` by default.
- When `version.match` is set, the first matching output line is selected before `regex` extraction.
- Required tool probe failure aborts shell startup.

Use `shell.packages` instead of `tools` when:

- the package should be in the shell but not in the banner
- the package is not a CLI tool with a stable version probe

## `config.release`

Shape:

```nix
{
  channels = [ "alpha" "beta" "rc" "internal" ];
  steps = [ ];
  postVersion = "";
  runtimeInputs = [ ];
}
```

Defaults:

- `channels = [ "alpha" "beta" "rc" "internal" ]`
- `steps = [ ]`
- `postVersion = ""`
- `runtimeInputs = [ ]`

Set `release = null` to disable the generated release package.

## Release step shapes

### `writeFile`

```nix
{
  writeFile = {
    path = "src/version.ts";
    text = ''
      export const APP_VERSION = "$FULL_VERSION" as const;
    '';
  };
}
```

### `replace`

```nix
{
  replace = {
    path = "README.md";
    regex = ''^(version = ")[^"]*(")$'';
    replacement = ''\1$FULL_VERSION\2'';
  };
}
```

### `versionMetaSet`

```nix
{
  versionMetaSet = {
    key = "desktop_binary_version_max";
    value = "$FULL_VERSION";
  };
}
```

### `versionMetaUnset`

```nix
{
  versionMetaUnset = {
    key = "desktop_unused";
  };
}
```

Rules:

- Current supported step kinds are only `writeFile`, `replace`, `versionMetaSet`, and `versionMetaUnset`.
- Do not document or implement a `run` step in consumer repos unless the library itself gains that feature.

## Release ordering

The generated `release` command currently does this:

1. Require a clean git worktree
2. Update `VERSION`
3. Run `release.steps`
4. Run `postVersion`
5. Run `nix fmt`
6. `git add -A`
7. Commit with `chore(release): <tag>`
8. Tag
9. Push branch
10. Push tags

Important consequences:

- `postVersion` is before formatting, commit, tag, and push.
- There is no true post-tag or post-push hook in current `repo-lib`.
- The current release runner is opinionated and performs commit, tag, and push as part of the flow.

## `mkRelease`

`repo-lib.lib.mkRelease` remains available when a repo wants only the release package:

```nix
repo-lib.lib.mkRelease {
  system = system;
  nixpkgsInput = nixpkgs; # optional
  channels = [ "alpha" "beta" "rc" "internal" ];
  steps = [ ];
  postVersion = "";
  runtimeInputs = [ ];
}
```

Use the same release-step rules as `config.release`.
