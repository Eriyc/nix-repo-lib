{
  lib,
  sanitizeName,
}:
let
  hookStageFileArgs =
    stage: passFilenames:
    if !passFilenames then
      ""
    else if stage == "pre-commit" then
      " {staged_files}"
    else if stage == "pre-push" then
      " {push_files}"
    else if stage == "commit-msg" then
      " {1}"
    else
      throw "repo-lib: unsupported lefthook stage '${stage}'";

  normalizeHookStage =
    hookName: stage:
    if
      builtins.elem stage [
        "pre-commit"
        "pre-push"
        "commit-msg"
      ]
    then
      stage
    else
      throw "repo-lib: hook '${hookName}' has unsupported stage '${stage}' for lefthook";
in
{
  inherit hookStageFileArgs normalizeHookStage;

  checkToLefthookConfig =
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
      lib.setAttrByPath [ check.stage "commands" name ] {
        run = "${wrapper}/bin/${wrapperName}${hookStageFileArgs check.stage check.passFilenames}";
      };

  normalizeLefthookConfig =
    label: raw: if builtins.isAttrs raw then raw else throw "repo-lib: ${label} must be an attrset";

  hookToLefthookConfig =
    name: hook:
    let
      supportedFields = [
        "description"
        "enable"
        "entry"
        "name"
        "package"
        "pass_filenames"
        "stages"
      ];
      unsupportedFields = builtins.filter (field: !(builtins.elem field supportedFields)) (
        builtins.attrNames hook
      );
      stages = builtins.map (stage: normalizeHookStage name stage) (hook.stages or [ "pre-commit" ]);
      passFilenames = hook.pass_filenames or false;
    in
    if unsupportedFields != [ ] then
      throw ''
        repo-lib: hook '${name}' uses unsupported fields for lefthook: ${lib.concatStringsSep ", " unsupportedFields}
      ''
    else if !(hook ? entry) then
      throw "repo-lib: hook '${name}' is missing 'entry'"
    else
      lib.foldl' lib.recursiveUpdate { } (
        builtins.map (
          stage:
          lib.setAttrByPath [ stage "commands" name ] {
            run = "${hook.entry}${hookStageFileArgs stage passFilenames}";
          }
        ) stages
      );

  parallelHookStageConfig =
    stage:
    if
      builtins.elem stage [
        "pre-commit"
        "pre-push"
      ]
    then
      lib.setAttrByPath [ stage "parallel" ] true
    else
      { };
}
