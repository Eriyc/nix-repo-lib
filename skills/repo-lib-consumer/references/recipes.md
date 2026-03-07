# repo-lib Change Recipes

## Add a new bannered tool

Edit `perSystem.tools` in the consuming repo:

```nix
tools = [
  (repo-lib.lib.tools.fromPackage {
    name = "Go";
    package = pkgs.go;
    version.args = [ "version" ];
    banner.color = "CYAN";
  })
];
```

Notes:

- Do not also add `pkgs.go` to `shell.packages`; `tools` already adds it.
- Use `exe = "name"` only when the package exposes multiple binaries or the main program is not the desired one.

## Add a non-banner package to the shell

Use `shell.packages`:

```nix
shell.packages = [
  self.packages.${system}.release
  pkgs.jq
];
```

Use this for:

- helper CLIs that do not need a banner entry
- internal scripts
- the generated `release` package itself

## Add a test phase or lint hook

For a simple global check:

```nix
config.checks.tests = {
  command = "go test ./...";
  stage = "pre-push";
  passFilenames = false;
  runtimeInputs = [ pkgs.go ];
};
```

For a system-specific check:

```nix
perSystem = { pkgs, ... }: {
  checks.lint = {
    command = "bun test";
    stage = "pre-push";
    runtimeInputs = [ pkgs.bun ];
  };
};
```

Guidance:

- Use `pre-commit` for fast format/lint work.
- Use `pre-push` for slower test suites.
- Prefer `runtimeInputs` over inline absolute paths when the command needs extra CLIs.

## Add or change formatters

Use `config.formatting`:

```nix
config.formatting = {
  programs = {
    shfmt.enable = true;
    gofmt.enable = true;
  };

  settings = {
    shfmt.options = [ "-i" "2" "-s" "-w" ];
  };
};
```

## Add release-managed files

Generate a file from the release version:

```nix
config.release.steps = [
  {
    writeFile = {
      path = "src/version.ts";
      text = ''
        export const APP_VERSION = "$FULL_VERSION" as const;
      '';
    };
  }
];
```

Update an existing file with a regex:

```nix
config.release.steps = [
  {
    replace = {
      path = "README.md";
      regex = ''^(version = ")[^"]*(")$'';
      replacement = ''\1$FULL_VERSION\2'';
    };
  }
];
```

## Add a webhook during release

If the webhook may run before commit and tag creation, use a `run` step or `postVersion`.

Use a `run` step when it belongs with other release mutations:

```nix
config.release = {
  runtimeInputs = [ pkgs.curl ];
  steps = [
    {
      run = {
        script = ''
          curl -fsS https://example.invalid/release-hook \
            -H 'content-type: application/json' \
            -d '{"version":"'"$FULL_VERSION"'"}'
        '';
        runtimeInputs = [ pkgs.curl ];
      };
    }
  ];
};
```

Use `postVersion` when the action should happen after all `steps`:

```nix
config.release.postVersion = ''
  curl -fsS https://example.invalid/release-hook \
    -H 'content-type: application/json' \
    -d '{"version":"'"$FULL_VERSION"'","tag":"'"$FULL_TAG"'"}'
'';
config.release.runtimeInputs = [ pkgs.curl ];
```

Important:

- Both of these still run before commit, tag, and push.
- They are not true post-tag hooks.

## Add a true post-tag webhook

Do not fake this with `postVersion`.

Preferred approach in the consuming repo:

1. Keep local release generation in `repo-lib`.
2. Add CI triggered by tag push.
3. Put the webhook call in CI, where the tag is already created and pushed.

Only change `repo-lib` itself if the user explicitly asks for a new local post-tag capability.

## Add impure bootstrap work

Only do this when the user actually wants imperative shell setup:

```nix
config.shell = {
  bootstrap = ''
    export GOBIN="$PWD/.tools/bin"
    export PATH="$GOBIN:$PATH"
  '';
  allowImpureBootstrap = true;
};
```

Do not add bootstrap work for normal Nix-packaged tools.

## Migrate a legacy consumer to `mkRepo`

Only do this if requested.

Migration outline:

1. Move repeated shell/check/formatter config into `config`.
2. Move old banner tools into `perSystem.tools`.
3. Move extra shell packages into `perSystem.shell.packages`.
4. Replace old `mkRelease { release = [ ... ]; }` with `config.release.steps`.
5. Keep behavior the same first; do not redesign the repo in the same change unless asked.
