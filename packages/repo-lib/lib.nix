{
  flake-parts,
  nixpkgs,
  treefmt-nix,
  lefthookNix,
  releaseScriptPath,
  shellHookTemplatePath,
}:
let
  defaults = import ./lib/defaults.nix { };
  common = import ./lib/common.nix { inherit nixpkgs; };
  normalizeShellBanner =
    rawBanner:
    let
      banner = defaults.defaultShellBanner // rawBanner;
    in
    if
      !(builtins.elem banner.style [
        "simple"
        "pretty"
      ])
    then
      throw "repo-lib: config.shell.banner.style must be one of simple or pretty"
    else
      banner;
  toolsModule = import ./lib/tools.nix {
    lib = common.lib;
  };
  hooksModule = import ./lib/hooks.nix {
    inherit (common) lib sanitizeName;
  };
  shellModule = import ./lib/shell.nix {
    inherit (common)
      lib
      ;
    inherit
      treefmt-nix
      lefthookNix
      shellHookTemplatePath
      ;
    inherit (defaults)
      defaultShellBanner
      ;
    inherit normalizeShellBanner;
    inherit (hooksModule)
      normalizeLefthookConfig
      parallelHookStageConfig
      checkToLefthookConfig
      hookToLefthookConfig
      ;
  };
  releaseModule = import ./lib/release.nix {
    inherit (common)
      lib
      importPkgs
      ;
    inherit
      nixpkgs
      releaseScriptPath
      ;
    inherit (defaults)
      defaultReleaseChannels
      ;
  };
  repoModule = import ./lib/repo.nix {
    inherit
      flake-parts
      nixpkgs
      ;
    inherit (common)
      lib
      importPkgs
      duplicateStrings
      mergeUniqueAttrs
      ;
    inherit (defaults)
      supportedSystems
      defaultReleaseChannels
      ;
    inherit (toolsModule)
      normalizeStrictTool
      ;
    inherit (hooksModule)
      normalizeLefthookConfig
      ;
    inherit normalizeShellBanner;
    inherit (shellModule)
      buildShellArtifacts
      ;
    inherit (releaseModule)
      mkRelease
      ;
  };
in
{
  systems.default = defaults.supportedSystems;
  inherit (toolsModule) tools;
  inherit (repoModule) normalizeRepoConfig mkRepo;
  inherit (releaseModule) mkRelease;
}
