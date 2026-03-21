{
  flake-parts,
  nixpkgs,
  lib,
  importPkgs,
  duplicateStrings,
  mergeUniqueAttrs,
  supportedSystems,
  defaultReleaseChannels,
  normalizeStrictTool,
  normalizeLefthookConfig,
  normalizeShellBanner,
  buildShellArtifacts,
  mkRelease,
}:
let
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
          banner = { };
        };
        formatting = {
          programs = { };
          settings = { };
        };
        checks = { };
        lefthook = { };
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
      merged
      // {
        inherit release;
        shell = merged.shell // {
          banner = normalizeShellBanner merged.shell.banner;
        };
      };

  buildRepoSystemOutputs =
    {
      pkgs,
      system,
      src,
      nixpkgsInput,
      normalizedConfig,
      userPerSystem,
    }:
    let
      perSystemResult = {
        tools = [ ];
        shell = { };
        checks = { };
        lefthook = { };
        packages = { };
        apps = { };
      }
      // userPerSystem {
        inherit pkgs system;
        lib = nixpkgs.lib;
        config = normalizedConfig;
      };

      strictTools = builtins.map (tool: normalizeStrictTool pkgs tool) perSystemResult.tools;
      duplicateToolNames = duplicateStrings (builtins.map (tool: tool.name) strictTools);
      mergedChecks = mergeUniqueAttrs "check" normalizedConfig.checks perSystemResult.checks;
      mergedLefthookConfig =
        lib.recursiveUpdate (normalizeLefthookConfig "config.lefthook" normalizedConfig.lefthook)
          (normalizeLefthookConfig "perSystem.lefthook" (perSystemResult.lefthook or { }));
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
            lefthookConfig = mergedLefthookConfig;
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
              nixpkgsInput = nixpkgsInput;
              channels = normalizedConfig.release.channels;
              steps = normalizedConfig.release.steps;
              postVersion = normalizedConfig.release.postVersion;
              runtimeInputs = normalizedConfig.release.runtimeInputs;
            };
          };
    in
    {
      checks = env.checks;
      formatter = env.formatter;
      shell = env.shell;
      packages = mergeUniqueAttrs "package" releasePackages perSystemResult.packages;
      apps = perSystemResult.apps;
    };
in
{
  inherit normalizeRepoConfig;

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
      userPerSystem = perSystem;
    in
    flake-parts.lib.mkFlake
      {
        inputs = {
          inherit self nixpkgs;
          flake-parts = flake-parts;
        };
      }
      {
        inherit systems;

        perSystem =
          {
            pkgs,
            system,
            ...
          }:
          let
            systemOutputs = buildRepoSystemOutputs {
              inherit
                pkgs
                system
                src
                normalizedConfig
                ;
              nixpkgsInput = nixpkgs;
              userPerSystem = userPerSystem;
            };
          in
          {
            devShells.default = systemOutputs.shell;
            inherit (systemOutputs)
              apps
              checks
              formatter
              packages
              ;
          };
      };
}
