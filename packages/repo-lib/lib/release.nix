{
  lib,
  nixpkgs,
  releaseScriptPath,
  defaultReleaseChannels,
  importPkgs,
}:
let
  normalizeReleaseStep =
    step:
    if step ? writeFile then
      {
        kind = "writeFile";
        path = step.writeFile.path;
        text = step.writeFile.text;
      }
    else if step ? replace then
      {
        kind = "replace";
        path = step.replace.path;
        regex = step.replace.regex;
        replacement = step.replace.replacement;
      }
    else if step ? versionMetaSet then
      {
        kind = "versionMetaSet";
        key = step.versionMetaSet.key;
        value = step.versionMetaSet.value;
      }
    else if step ? versionMetaUnset then
      {
        kind = "versionMetaUnset";
        key = step.versionMetaUnset.key;
      }
    else
      throw "repo-lib: release step must contain one of writeFile, replace, versionMetaSet, or versionMetaUnset";

  normalizeReleaseConfig =
    raw:
    let
      steps = if raw ? steps then builtins.map normalizeReleaseStep raw.steps else [ ];
    in
    {
      postVersion = raw.postVersion or "";
      channels = raw.channels or defaultReleaseChannels;
      runtimeInputs = raw.runtimeInputs or [ ];
      steps = steps;
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
      releaseStepsJson = builtins.toJSON release.steps;
      releaseRunner = pkgs.buildGoModule {
        pname = "repo-lib-release-runner";
        version = "0.0.0";
        src = ../../release;
        vendorHash = "sha256-fGFteYruAda2MBHkKgbTeCpIgO30tKCa+tzF6HcUvWM=";
        subPackages = [ "cmd/release" ];
      };
      script =
        builtins.replaceStrings
          [
            "__CHANNEL_LIST__"
            "__RELEASE_STEPS_JSON__"
            "__POST_VERSION__"
            "__RELEASE_RUNNER__"
          ]
          [
            channelList
            releaseStepsJson
            release.postVersion
            (lib.getExe' releaseRunner "release")
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
        ]
        ++ release.runtimeInputs;
      text = script;
    };
in
{
  inherit
    normalizeReleaseStep
    normalizeReleaseConfig
    mkRelease
    ;
}
