# release.nix
{
  pkgs,
  postVersion ? "",
  release ? [ ],
  # Unified list, processed in declaration order:
  #   { file = "path/to/file"; content = "..."; }   — write file
  #   { run = "shell snippet..."; }                  — run script
  channels ? [
    "alpha"
    "beta"
    "rc"
    "internal"
  ],
  extraRuntimeInputs ? [ ],
}:
let
  channelList = pkgs.lib.concatStringsSep " " channels;

  releaseScript = pkgs.lib.concatMapStrings (
    entry:
    if entry ? file then
      ''
        mkdir -p "$(dirname "${entry.file}")"
        cat > "${entry.file}" << NIXEOF
        ${entry.content}
        NIXEOF
        log "Generated version file: ${entry.file}"
      ''
    else if entry ? run then
      ''
        ${entry.run}
      ''
    else
      builtins.throw "release entry must have either 'file' or 'run'"
  ) release;

  script =
    builtins.replaceStrings
      [ "__CHANNEL_LIST__" "__RELEASE_STEPS__" "__POST_VERSION__" ]
      [ channelList releaseScript postVersion ]
      (builtins.readFile ./release.sh);
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
    ++ extraRuntimeInputs;
  text = script;
}
