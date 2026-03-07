{
  nixpkgs,
  treefmt-nix,
  git-hooks,
  releaseScriptPath,
  shellHookTemplatePath,
}:
let
  lib = nixpkgs.lib;

  supportedSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  defaultReleaseChannels = [
    "alpha"
    "beta"
    "rc"
    "internal"
  ];

  importPkgs = nixpkgsInput: system: import nixpkgsInput { inherit system; };

  duplicateStrings =
    names:
    lib.unique (
      builtins.filter (
        name: builtins.length (builtins.filter (candidate: candidate == name) names) > 1
      ) names
    );

  mergeUniqueAttrs =
    label: left: right:
    let
      overlap = builtins.attrNames (lib.intersectAttrs left right);
    in
    if overlap != [ ] then
      throw "repo-lib: duplicate ${label}: ${lib.concatStringsSep ", " overlap}"
    else
      left // right;

  sanitizeName = name: lib.strings.sanitizeDerivationName name;

  normalizeStrictTool =
    pkgs: tool:
    let
      version = {
        args = [ "--version" ];
        regex = null;
        group = 0;
        line = 1;
      }
      // (tool.version or { });
      banner = {
        color = "YELLOW";
      }
      // (tool.banner or { });
      executable =
        if tool ? exe && tool.exe != null then
          "${lib.getExe' tool.package tool.exe}"
        else
          "${lib.getExe tool.package}";
    in
    if !(tool ? package) then
      throw "repo-lib: tool '${tool.name or "<unnamed>"}' is missing 'package'"
    else
      {
        kind = "strict";
        inherit executable version banner;
        name = tool.name;
        package = tool.package;
        required = tool.required or true;
      };

  normalizeLegacyTool =
    pkgs: tool:
    if tool ? package then
      normalizeStrictTool pkgs tool
    else
      {
        kind = "legacy";
        name = tool.name;
        command = tool.bin;
        versionCommand = tool.versionCmd or "--version";
        banner = {
          color = tool.color or "YELLOW";
        };
        required = tool.required or false;
      };

  normalizeCheck =
    pkgs: name: rawCheck:
    let
      check = {
        stage = "pre-commit";
        passFilenames = false;
        runtimeInputs = [ ];
      }
      // rawCheck;
      wrapperName = "repo-lib-check-${sanitizeName name}";
      wrapper = pkgs.writeShellApplication {
        name = wrapperName;
        runtimeInputs = check.runtimeInputs;
        text = ''
          set -euo pipefail
          ${check.command}
        '';
      };
    in
    if !(check ? command) then
      throw "repo-lib: check '${name}' is missing 'command'"
    else if
      !(builtins.elem check.stage [
        "pre-commit"
        "pre-push"
      ])
    then
      throw "repo-lib: check '${name}' has unsupported stage '${check.stage}'"
    else
      {
        enable = true;
        entry = "${wrapper}/bin/${wrapperName}";
        pass_filenames = check.passFilenames;
        stages = [ check.stage ];
      };

  normalizeReleaseStep =
    step:
    if step ? writeFile then
      {
        kind = "writeFile";
        path = step.writeFile.path;
        text = step.writeFile.text;
        runtimeInputs = [ ];
      }
    else if step ? replace then
      {
        kind = "replace";
        path = step.replace.path;
        regex = step.replace.regex;
        replacement = step.replace.replacement;
        runtimeInputs = [ ];
      }
    else if step ? run && builtins.isAttrs step.run then
      {
        kind = "run";
        script = step.run.script;
        runtimeInputs = step.run.runtimeInputs or [ ];
      }
    else if step ? run then
      {
        kind = "run";
        script = step.run;
        runtimeInputs = [ ];
      }
    else if step ? file then
      {
        kind = "writeFile";
        path = step.file;
        text = step.content;
        runtimeInputs = [ ];
      }
    else
      throw "repo-lib: release step must contain one of writeFile, replace, or run";

  releaseStepScript =
    step:
    if step.kind == "writeFile" then
      ''
        target_path="$ROOT_DIR/${step.path}"
        mkdir -p "$(dirname "$target_path")"
        cat >"$target_path" << NIXEOF
        ${step.text}
        NIXEOF
        log "Generated version file: ${step.path}"
      ''
    else if step.kind == "replace" then
      ''
        target_path="$ROOT_DIR/${step.path}"
        REPO_LIB_STEP_REGEX=$(cat <<'NIXEOF'
        ${step.regex}
        NIXEOF
        )
        REPO_LIB_STEP_REPLACEMENT=$(cat <<NIXEOF
        ${step.replacement}
        NIXEOF
        )
        export REPO_LIB_STEP_REGEX REPO_LIB_STEP_REPLACEMENT
        perl -0pi -e 'my $regex = $ENV{"REPO_LIB_STEP_REGEX"}; my $replacement = $ENV{"REPO_LIB_STEP_REPLACEMENT"}; s/$regex/$replacement/gms;' "$target_path"
        log "Updated ${step.path}"
      ''
    else
      ''
        ${step.script}
      '';

  normalizeReleaseConfig =
    raw:
    let
      hasLegacySteps = raw ? release;
      hasStructuredSteps = raw ? steps;
      steps =
        if hasLegacySteps && hasStructuredSteps then
          throw "repo-lib: pass either 'release' or 'steps' to mkRelease, not both"
        else if hasStructuredSteps then
          builtins.map normalizeReleaseStep raw.steps
        else if hasLegacySteps then
          builtins.map normalizeReleaseStep raw.release
        else
          [ ];
    in
    {
      postVersion = raw.postVersion or "";
      channels = raw.channels or defaultReleaseChannels;
      runtimeInputs = (raw.runtimeInputs or [ ]) ++ (raw.extraRuntimeInputs or [ ]);
      steps = steps;
    };

  buildShellHook =
    {
      preCommitShellHook,
      shellEnvScript,
      bootstrap,
      toolBannerScript,
      extraShellText,
      toolLabelWidth,
    }:
    let
      template = builtins.readFile shellHookTemplatePath;
    in
    builtins.replaceStrings
      [
        "\${pre-commit-check.shellHook}"
        "@TOOL_LABEL_WIDTH@"
        "@SHELL_ENV_SCRIPT@"
        "@BOOTSTRAP@"
        "@TOOL_BANNER_SCRIPT@"
        "@EXTRA_SHELL_TEXT@"
      ]
      [
        preCommitShellHook
        (toString toolLabelWidth)
        shellEnvScript
        bootstrap
        toolBannerScript
        extraShellText
      ]
      template;

  buildShellArtifacts =
    {
      pkgs,
      system,
      src,
      includeStandardPackages ? true,
      formatting,
      tools ? [ ],
      shellConfig ? {
        env = { };
        extraShellText = "";
        bootstrap = "";
      },
      checkSpecs ? { },
      rawHookEntries ? { },
      extraPackages ? [ ],
    }:
    let
      standardPackages = with pkgs; [
        nixfmt
        gitlint
        gitleaks
        shfmt
      ];
      toolPackages = lib.filter (pkg: pkg != null) (builtins.map (tool: tool.package or null) tools);
      selectedStandardPackages = lib.optionals includeStandardPackages standardPackages;

      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt.enable = true;
        }
        // formatting.programs;
        settings.formatter = { } // formatting.settings;
      };

      normalizedChecks = lib.mapAttrs (name: check: normalizeCheck pkgs name check) checkSpecs;
      hooks = mergeUniqueAttrs "hook" rawHookEntries normalizedChecks;

      pre-commit-check = git-hooks.lib.${system}.run {
        inherit src;
        hooks = {
          treefmt = {
            enable = true;
            entry = "${treefmtEval.config.build.wrapper}/bin/treefmt --ci";
            pass_filenames = true;
          };
          gitlint.enable = true;
          gitleaks = {
            enable = true;
            entry = "${pkgs.gitleaks}/bin/gitleaks protect --staged";
            pass_filenames = false;
          };
        }
        // hooks;
      };

      toolNames = builtins.map (tool: tool.name) tools;
      toolNameWidth =
        if toolNames == [ ] then
          0
        else
          builtins.foldl' (maxWidth: name: lib.max maxWidth (builtins.stringLength name)) 0 toolNames;
      toolLabelWidth = toolNameWidth + 1;

      shellEnvScript = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: value: "export ${name}=${lib.escapeShellArg (toString value)}"
        ) shellConfig.env
      );

      toolBannerScript = lib.concatMapStrings (
        tool:
        if tool.kind == "strict" then
          ''
            repo_lib_probe_tool \
              ${lib.escapeShellArg tool.name} \
              ${lib.escapeShellArg tool.banner.color} \
              ${lib.escapeShellArg (if tool.required then "1" else "0")} \
              ${lib.escapeShellArg (toString tool.version.line)} \
              ${lib.escapeShellArg (toString tool.version.group)} \
              ${lib.escapeShellArg (tool.version.regex or "")} \
              ${lib.escapeShellArg tool.executable} \
              ${lib.escapeShellArgs tool.version.args}
          ''
        else
          ''
            repo_lib_probe_legacy_tool \
              ${lib.escapeShellArg tool.name} \
              ${lib.escapeShellArg tool.banner.color} \
              ${lib.escapeShellArg (if tool.required then "1" else "0")} \
              ${lib.escapeShellArg tool.command} \
              ${lib.escapeShellArg tool.versionCommand}
          ''
      ) tools;
    in
    {
      inherit pre-commit-check;
      formatter = treefmtEval.config.build.wrapper;
      shell = pkgs.mkShell {
        packages = lib.unique (selectedStandardPackages ++ extraPackages ++ toolPackages);
        buildInputs = pre-commit-check.enabledPackages;
        shellHook = buildShellHook {
          preCommitShellHook = pre-commit-check.shellHook;
          inherit toolLabelWidth shellEnvScript toolBannerScript;
          bootstrap = shellConfig.bootstrap;
          extraShellText = shellConfig.extraShellText;
        };
      };
    };
in
rec {
  systems = {
    default = supportedSystems;
  };

  tools = rec {
    fromPackage =
      {
        name,
        package,
        exe ? null,
        version ? { },
        banner ? { },
        required ? true,
      }:
      {
        inherit
          name
          package
          exe
          version
          banner
          required
          ;
      };

    simple =
      name: package: args:
      fromPackage {
        inherit name package;
        version.args = args;
      };
  };

  normalizeRepoConfig =
    rawConfig:
    let
      merged = lib.recursiveUpdate {
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
        release = null;
      } rawConfig;
      release =
        if merged.release == null then
          null
        else
          {
            channels = defaultReleaseChannels;
            steps = [ ];
            postVersion = "";
            runtimeInputs = [ ];
          }
          // merged.release;
    in
    if merged.shell.bootstrap != "" && !merged.shell.allowImpureBootstrap then
      throw "repo-lib: config.shell.bootstrap requires config.shell.allowImpureBootstrap = true"
    else
      merged // { inherit release; };

  mkDevShell =
    {
      system,
      src ? ./.,
      nixpkgsInput ? nixpkgs,
      extraPackages ? [ ],
      preToolHook ? "",
      extraShellHook ? "",
      additionalHooks ? { },
      tools ? [ ],
      includeStandardPackages ? true,
      formatters ? { },
      formatterSettings ? { },
      features ? { },
    }:
    let
      pkgs = importPkgs nixpkgsInput system;
      oxfmtEnabled = features.oxfmt or false;
      legacyTools = builtins.map (tool: normalizeLegacyTool pkgs tool) tools;
      duplicateToolNames = duplicateStrings (builtins.map (tool: tool.name) legacyTools);
      normalizedFormatting = {
        programs =
          (lib.optionalAttrs oxfmtEnabled {
            oxfmt.enable = true;
          })
          // formatters;
        settings = formatterSettings;
      };
      shellConfig = {
        env = { };
        extraShellText = extraShellHook;
        allowImpureBootstrap = true;
        bootstrap = preToolHook;
      };
    in
    if duplicateToolNames != [ ] then
      throw "repo-lib: duplicate tool names: ${lib.concatStringsSep ", " duplicateToolNames}"
    else
      buildShellArtifacts {
        inherit
          pkgs
          system
          src
          includeStandardPackages
          ;
        formatting = normalizedFormatting;
        rawHookEntries = additionalHooks;
        shellConfig = shellConfig;
        tools = legacyTools;
        extraPackages =
          extraPackages
          ++ lib.optionals oxfmtEnabled [
            pkgs.oxfmt
            pkgs.oxlint
          ];
      };

  mkRelease =
    {
      system,
      nixpkgsInput ? nixpkgs,
      ...
    }@rawArgs:
    let
      pkgs = importPkgs nixpkgsInput system;
      release = normalizeReleaseConfig rawArgs;
      channelList = lib.concatStringsSep " " release.channels;
      releaseStepsScript = lib.concatMapStrings releaseStepScript release.steps;
      script =
        builtins.replaceStrings
          [
            "__CHANNEL_LIST__"
            "__RELEASE_STEPS__"
            "__POST_VERSION__"
          ]
          [
            channelList
            releaseStepsScript
            release.postVersion
          ]
          (builtins.readFile releaseScriptPath);
    in
    pkgs.writeShellApplication {
      name = "release";
      runtimeInputs =
        with pkgs;
        [
          git
          gnugrep
          gawk
          gnused
          coreutils
          perl
        ]
        ++ release.runtimeInputs
        ++ lib.concatMap (step: step.runtimeInputs or [ ]) release.steps;
      text = script;
    };

  mkRepo =
    {
      self,
      nixpkgs,
      src ? ./.,
      systems ? supportedSystems,
      config ? { },
      perSystem ? (
        {
          pkgs,
          system,
          lib,
          config,
        }:
        { }
      ),
    }:
    let
      normalizedConfig = normalizeRepoConfig config;
      systemResults = lib.genAttrs systems (
        system:
        let
          pkgs = importPkgs nixpkgs system;
          perSystemResult = {
            tools = [ ];
            shell = { };
            checks = { };
            packages = { };
            apps = { };
          }
          // perSystem {
            inherit pkgs system;
            lib = nixpkgs.lib;
            config = normalizedConfig;
          };

          strictTools = builtins.map (tool: normalizeStrictTool pkgs tool) perSystemResult.tools;
          duplicateToolNames = duplicateStrings (builtins.map (tool: tool.name) strictTools);
          mergedChecks = mergeUniqueAttrs "check" normalizedConfig.checks perSystemResult.checks;
          shellConfig = lib.recursiveUpdate normalizedConfig.shell (perSystemResult.shell or { });
          env =
            if duplicateToolNames != [ ] then
              throw "repo-lib: duplicate tool names: ${lib.concatStringsSep ", " duplicateToolNames}"
            else
              buildShellArtifacts {
                inherit
                  pkgs
                  system
                  src
                  ;
                includeStandardPackages = normalizedConfig.includeStandardPackages;
                formatting = normalizedConfig.formatting;
                tools = strictTools;
                checkSpecs = mergedChecks;
                shellConfig = shellConfig;
                extraPackages = perSystemResult.shell.packages or [ ];
              };

          releasePackages =
            if normalizedConfig.release == null then
              { }
            else
              {
                release = mkRelease {
                  inherit system;
                  nixpkgsInput = nixpkgs;
                  channels = normalizedConfig.release.channels;
                  steps = normalizedConfig.release.steps;
                  postVersion = normalizedConfig.release.postVersion;
                  runtimeInputs = normalizedConfig.release.runtimeInputs;
                };
              };
        in
        {
          inherit env;
          packages = mergeUniqueAttrs "package" releasePackages perSystemResult.packages;
          apps = perSystemResult.apps;
        }
      );
    in
    {
      devShells = lib.genAttrs systems (system: {
        default = systemResults.${system}.env.shell;
      });

      checks = lib.genAttrs systems (system: {
        inherit (systemResults.${system}.env) pre-commit-check;
      });

      formatter = lib.genAttrs systems (system: systemResults.${system}.env.formatter);
      packages = lib.genAttrs systems (system: systemResults.${system}.packages);
      apps = lib.genAttrs systems (system: systemResults.${system}.apps);
    };
}
