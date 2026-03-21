# repo-lib Change Recipes

## Add a new bannered tool

Edit `perSystem.tools` in the consuming repo:

```nix
tools = [
  (repo-lib.lib.tools.fromPackage {
    name = "Bun";
    package = pkgs.bun;
    version.args = [ "--version" ];
    banner = {
      color = "YELLOW";
      icon = "";
    };
  })
];
```

Notes:

- Do not also add the same package to `shell.packages`; `tools` already adds package-backed tools to the shell.
- Use `exe = "name"` only when the package exposes multiple binaries or the default binary is not the right one.
- Use `fromCommand` when the executable should come from the host environment instead of `nixpkgs`.

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

## Customize the shell banner

Use `config.shell.banner`:

```nix
config.shell.banner = {
  style = "pretty";
  icon = "☾";
  title = "Moonrepo shell ready";
  titleColor = "GREEN";
  subtitle = "Bun + TypeScript + Varlock";
  subtitleColor = "GRAY";
  borderColor = "BLUE";
};
```

Guidance:

- Use `style = "pretty"` when the repo already has a styled shell banner.
- Keep icons and colors consistent with the repo's current shell UX.
- Remember that required tool probe failures will still abort shell startup.

## Add a test phase or lint hook

For a simple shared check:

```nix
config.checks.typecheck = {
  command = "bun run typecheck";
  stage = "pre-push";
  passFilenames = false;
  runtimeInputs = [ pkgs.bun ];
};
```

For a system-specific check:

```nix
perSystem = { pkgs, ... }: {
  checks.format = {
    command = "oxfmt --check .";
    stage = "pre-commit";
    passFilenames = false;
    runtimeInputs = [ pkgs.oxfmt ];
  };
};
```

Guidance:

- Use `pre-commit` for fast format or lint work.
- Use `pre-push` for slower test suites.
- Prefer `runtimeInputs` over inline absolute paths when the command needs extra CLIs.

## Add a `commit-msg` hook

`config.checks` cannot target `commit-msg`. Use raw Lefthook config:

```nix
config.lefthook.commit-msg.commands.gitlint = {
  run = "${pkgs.gitlint}/bin/gitlint --staged --msg-filename {1}";
  stage_fixed = true;
};
```

Or use a structured hook entry:

```nix
perSystem = { pkgs, ... }: {
  lefthook.commitlint = {
    entry = "${pkgs.nodejs}/bin/node scripts/commitlint.mjs";
    pass_filenames = true;
    stages = [ "commit-msg" ];
  };
};
```

## Add or change formatters

Use `config.formatting`:

```nix
config.formatting = {
  programs = {
    shfmt.enable = true;
    oxfmt.enable = true;
  };

  settings = {
    shfmt.options = [ "-i" "2" "-s" "-w" ];
    oxfmt.excludes = [ "*.md" "*.yml" ];
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

Update metadata inside `VERSION`:

```nix
config.release.steps = [
  {
    versionMetaSet = {
      key = "desktop_binary_version_max";
      value = "$FULL_VERSION";
    };
  }
  {
    versionMetaUnset = {
      key = "desktop_unused";
    };
  }
];
```

## Add a webhook during release

Current `repo-lib` does not expose a `run` release step. If the action must happen during local release execution, put it in `postVersion`:

```nix
config.release.postVersion = ''
  curl -fsS https://example.invalid/release-hook \
    -H 'content-type: application/json' \
    -d '{"version":"'"$FULL_VERSION"'","tag":"'"$FULL_TAG"'"}'
'';
config.release.runtimeInputs = [ pkgs.curl ];
```

Important:

- `postVersion` still runs before `nix fmt`, commit, tag, and push.
- This is not a true post-tag hook.

## Add a true post-tag webhook

Do not fake this with `postVersion`.

Preferred approach in the consuming repo:

1. Keep local version generation in `repo-lib`.
2. Trigger CI from tag push.
3. Put the webhook call in CI, where the tag already exists remotely.

Only change `repo-lib` itself if the user explicitly asks for a new library capability.

## Add impure bootstrap work

Only do this when the user actually wants imperative shell setup:

```nix
config.shell = {
  bootstrap = ''
    export BUN_INSTALL_GLOBAL_DIR="$PWD/.tools/bun/install/global"
    export BUN_INSTALL_BIN="$PWD/.tools/bun/bin"
    export PATH="$BUN_INSTALL_BIN:$PATH"
  '';
  allowImpureBootstrap = true;
};
```

Do not add bootstrap work for normal Nix-packaged tools.

## Move from direct `mkRelease` to `mkRepo`

Only do this if requested.

Migration outline:

1. Move release package config into `config.release`.
2. Move shell setup into `config.shell` and `perSystem.shell.packages`.
3. Move bannered CLIs into `perSystem.tools`.
4. Move hook commands into `config.checks` or raw `lefthook`.
5. Keep behavior the same first; do not redesign the repo in the same change unless asked.
