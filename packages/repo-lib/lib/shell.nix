{
  lib,
  treefmt-nix,
  lefthookNix,
  shellHookTemplatePath,
  defaultShellBanner,
  normalizeShellBanner,
  normalizeLefthookConfig,
  parallelHookStageConfig,
  checkToLefthookConfig,
  hookToLefthookConfig,
}:
let
  buildShellHook =
    {
      hooksShellHook,
      shellEnvScript,
      bootstrap,
      shellBannerScript,
      extraShellText,
      toolLabelWidth,
    }:
    let
      template = builtins.readFile shellHookTemplatePath;
    in
    builtins.replaceStrings
      [
        "@HOOKS_SHELL_HOOK@"
        "@TOOL_LABEL_WIDTH@"
        "@SHELL_ENV_SCRIPT@"
        "@BOOTSTRAP@"
        "@SHELL_BANNER_SCRIPT@"
        "@EXTRA_SHELL_TEXT@"
      ]
      [
        hooksShellHook
        (toString toolLabelWidth)
        shellEnvScript
        bootstrap
        shellBannerScript
        extraShellText
      ]
      template;
in
{
  inherit buildShellHook;

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
        banner = defaultShellBanner;
      },
      checkSpecs ? { },
      rawHookEntries ? { },
      lefthookConfig ? { },
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
      treefmtWrapper = treefmtEval.config.build.wrapper;
      lefthookBinWrapper = pkgs.writeShellScript "lefthook-dumb-term" ''
        exec env TERM=dumb ${lib.getExe pkgs.lefthook} "$@"
      '';

      normalizedLefthookConfig = normalizeLefthookConfig "lefthook config" lefthookConfig;
      lefthookCheck = lefthookNix.lib.${system}.run {
        inherit src;
        config = lib.foldl' lib.recursiveUpdate { } (
          [
            {
              output = [
                "failure"
                "summary"
              ];
            }
            (parallelHookStageConfig "pre-commit")
            (parallelHookStageConfig "pre-push")
            (lib.setAttrByPath [ "pre-commit" "commands" "treefmt" ] {
              run = "${treefmtWrapper}/bin/treefmt --no-cache {staged_files}";
              stage_fixed = true;
            })
            (lib.setAttrByPath [ "pre-commit" "commands" "gitleaks" ] {
              run = "${pkgs.gitleaks}/bin/gitleaks protect --staged";
            })
            (lib.setAttrByPath [ "commit-msg" "commands" "gitlint" ] {
              run = "${pkgs.gitlint}/bin/gitlint --staged --msg-filename {1}";
            })
          ]
          ++ lib.mapAttrsToList (name: check: checkToLefthookConfig pkgs name check) checkSpecs
          ++ lib.mapAttrsToList hookToLefthookConfig rawHookEntries
          ++ [ normalizedLefthookConfig ]
        );
      };
      selectedCheckOutputs = {
        formatting-check = treefmtEval.config.build.check src;
        hook-check = lefthookCheck;
        lefthook-check = lefthookCheck;
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

      banner = normalizeShellBanner (shellConfig.banner or { });

      shellBannerScript =
        if banner.style == "pretty" then
          ''
            repo_lib_print_pretty_header \
              ${lib.escapeShellArg banner.borderColor} \
              ${lib.escapeShellArg banner.titleColor} \
              ${lib.escapeShellArg banner.icon} \
              ${lib.escapeShellArg banner.title} \
              ${lib.escapeShellArg banner.subtitleColor} \
              ${lib.escapeShellArg banner.subtitle}
          ''
          + lib.concatMapStrings (tool: ''
            repo_lib_print_pretty_tool \
              ${lib.escapeShellArg banner.borderColor} \
              ${lib.escapeShellArg tool.name} \
              ${lib.escapeShellArg tool.banner.color} \
              ${lib.escapeShellArg (if tool.banner.icon == null then "" else tool.banner.icon)} \
              ${lib.escapeShellArg (if tool.banner.iconColor == null then "" else tool.banner.iconColor)} \
              ${lib.escapeShellArg (if tool.required then "1" else "0")} \
              ${lib.escapeShellArg (toString tool.version.line)} \
              ${lib.escapeShellArg (toString tool.version.group)} \
              ${lib.escapeShellArg (if tool.version.regex == null then "" else tool.version.regex)} \
              ${lib.escapeShellArg (if tool.version.match == null then "" else tool.version.match)} \
              ${lib.escapeShellArg tool.executable} \
              ${lib.escapeShellArgs tool.version.args}
          '') tools
          + ''
            repo_lib_print_pretty_footer \
              ${lib.escapeShellArg banner.borderColor}
          ''
        else
          ''
            repo_lib_print_simple_header \
              ${lib.escapeShellArg banner.titleColor} \
              ${lib.escapeShellArg banner.icon} \
              ${lib.escapeShellArg banner.title} \
              ${lib.escapeShellArg banner.subtitleColor} \
              ${lib.escapeShellArg banner.subtitle}
          ''
          + lib.concatMapStrings (tool: ''
            repo_lib_print_simple_tool \
              ${lib.escapeShellArg tool.name} \
              ${lib.escapeShellArg tool.banner.color} \
              ${lib.escapeShellArg (if tool.banner.icon == null then "" else tool.banner.icon)} \
              ${lib.escapeShellArg (if tool.banner.iconColor == null then "" else tool.banner.iconColor)} \
              ${lib.escapeShellArg (if tool.required then "1" else "0")} \
              ${lib.escapeShellArg (toString tool.version.line)} \
              ${lib.escapeShellArg (toString tool.version.group)} \
              ${lib.escapeShellArg (if tool.version.regex == null then "" else tool.version.regex)} \
              ${lib.escapeShellArg (if tool.version.match == null then "" else tool.version.match)} \
              ${lib.escapeShellArg tool.executable} \
              ${lib.escapeShellArgs tool.version.args}
          '') tools
          + ''
            printf "\n"
          '';
    in
    {
      checks = selectedCheckOutputs;
      formatter = treefmtWrapper;
      shell = pkgs.mkShell {
        LEFTHOOK_BIN = builtins.toString lefthookBinWrapper;
        packages = lib.unique (
          selectedStandardPackages
          ++ extraPackages
          ++ toolPackages
          ++ [
            pkgs.lefthook
            treefmtWrapper
          ]
        );
        shellHook = buildShellHook {
          hooksShellHook = lefthookCheck.shellHook;
          inherit toolLabelWidth shellEnvScript shellBannerScript;
          bootstrap = shellConfig.bootstrap;
          extraShellText = shellConfig.extraShellText;
        };
      };
    }
    // selectedCheckOutputs;
}
