# release.nix
{
  pkgs,
  readVersion,
  writeVersion,
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
        "__READ_VERSION__"
        "__WRITE_VERSION__"
        "__POST_VERSION__"
      ]
      [
        channelList
        versionFilesScript
        readVersion
        writeVersion
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
