# repo-lib Consumer API

## Detect the repo shape

Look for one of these patterns in the consuming repo:

- `repo-lib.lib.mkRepo`
- `repo-lib.lib.mkDevShell`
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
    };

    formatting = {
      programs = { };
      settings = { };
    };

    checks = { };

    release = null; # or attrset below
  };

  perSystem = { pkgs, system, lib, config }: {
    tools = [ ];
    shell.packages = [ ];
    checks = { };
    packages = { };
    apps = { };
  };
}
```

Generated outputs:

- `devShells.${system}.default`
- `checks.${system}.hook-check`
- `checks.${system}.lefthook-check`
- `formatter.${system}`
- `packages.${system}.release` when `config.release != null`
- merged `packages` and `apps` from `perSystem`

## `config.shell`

Fields:

- `env`
  Attrset of environment variables exported in the shell.
- `extraShellText`
  Extra shell snippet appended after the banner.
- `bootstrap`
  Shell snippet that runs before the banner.
- `allowImpureBootstrap`
  Must be `true` if `bootstrap` is non-empty.

Rules:

- Default is pure-first.
- Do not add bootstrap work unless the user actually wants imperative setup.
- Use `bootstrap` for unavoidable local setup only.

## `config.formatting`

Fields:

- `programs`
  Passed to `treefmt-nix.lib.evalModule`.
- `settings`
  Passed to `settings.formatter`.

Rules:

- `nixfmt` is always enabled.
- Use formatter settings instead of ad hoc shell formatting logic.

## Checks

`config.checks.<name>` and `perSystem.checks.<name>` use this shape:

```nix
{
  command = "go test ./...";
  stage = "pre-push"; # or "pre-commit"
  passFilenames = false;
  runtimeInputs = [ pkgs.go ];
}
```

Defaults:

- `stage = "pre-commit"`
- `passFilenames = false`
- `runtimeInputs = [ ]`

Rules:

- Only `pre-commit` and `pre-push` are supported.
- The command is wrapped as a script and connected into `lefthook.nix`.
- `pre-commit` and `pre-push` commands are configured to run in parallel.

## Tools

Preferred shape in `perSystem.tools`:

```nix
(repo-lib.lib.tools.fromPackage {
  name = "Go";
  package = pkgs.go;
  exe = "go"; # optional
  version = {
    args = [ "version" ];
    regex = null;
    group = 0;
    line = 1;
  };
  banner = {
    color = "CYAN";
  };
  required = true;
})
```

For a tool that should come from the host `PATH` instead of `nixpkgs`:

```nix
(repo-lib.lib.tools.fromCommand {
  name = "Nix";
  command = "nix";
  version.args = [ "--version" ];
})
```

Helper:

```nix
repo-lib.lib.tools.simple "Go" pkgs.go [ "version" ]
```

Tool behavior:

- Tool packages are added to the shell automatically.
- Command-backed tools are probed from the existing `PATH` and are not added to the shell automatically.
- Banner probing uses absolute executable paths.
- `required = true` by default.
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

### `run`

```nix
{
  run = {
    script = ''
      curl -fsS https://example.invalid/hook \
        -H 'content-type: application/json' \
        -d '{"tag":"'"$FULL_TAG"'"}'
    '';
    runtimeInputs = [ pkgs.curl ];
  };
}
```

Also accepted for compatibility:

- `{ run = ''...''; }`
- legacy `mkRelease { release = [ { file = ...; content = ...; } ... ]; }`

## Release ordering

The generated `release` command does this:

1. Update `VERSION`
2. Run `release.steps`
3. Run `postVersion`
4. Run `nix fmt`
5. `git add -A`
6. Commit
7. Tag
8. Push branch
9. Push tags

Important consequence:

- `postVersion` is still before commit, tag, and push.
- There is no true post-tag or post-push hook in current `repo-lib`.

## Post-tag webhook limitation

If the user asks for a webhook after the tag exists remotely:

- Prefer CI triggered by pushed tags in the consuming repo.
- Do not claim `postVersion` is post-tag; it is not.
- Only extend `repo-lib` itself if the user explicitly wants a new library capability.

## Legacy API summary

`mkDevShell` still supports:

- `extraPackages`
- `preToolHook`
- `extraShellHook`
- `additionalHooks`
- old `tools = [ { name; bin; versionCmd; color; } ]`
- `features.oxfmt`
- `formatters`
- `formatterSettings`

`mkRelease` still supports:

- `release = [ ... ]` as legacy alias for `steps`
- `extraRuntimeInputs` as legacy alias merged into `runtimeInputs`

When a repo already uses these APIs:

- preserve them unless the user asked to migrate
- do not mix old and new styles accidentally in the same call
