# release.nix
{
  pkgs,
  # Source of truth is always $ROOT_DIR/VERSION.
  # Format:
  #   line 1: X.Y.Z
  #   line 2: CHANNEL (stable|alpha|beta|rc|internal|...)
  #   line 3: N (prerelease number, 0 for stable)
  postVersion ? "",
  versionFiles ? [ ],
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

  versionFilesScript = pkgs.lib.concatMapStrings (f: ''
    mkdir -p "$(dirname "${f.path}")"
    ${f.content} > "${f.path}"
    log "Generated version file: ${f.path}"
  '') versionFiles;

  script =
    builtins.replaceStrings
      [
        "__CHANNEL_LIST__"
        "__VERSION_FILES__"
        "__POST_VERSION__"
      ]
      [
        channelList
        versionFilesScript
        postVersion
      ]
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
