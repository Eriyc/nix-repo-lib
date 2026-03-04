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
        "__READ_VERSION__"
        "__WRITE_VERSION__"
        "__POST_VERSION__"
      ]
      [
        channelList
        versionFilesScript
        ''
          if [[ ! -f "$ROOT_DIR/VERSION" ]]; then
            echo "Error: missing $ROOT_DIR/VERSION" >&2
            exit 1
          fi

          base_line="$(sed -n '1p' "$ROOT_DIR/VERSION" | tr -d '\r')"
          channel_line="$(sed -n '2p' "$ROOT_DIR/VERSION" | tr -d '\r')"
          n_line="$(sed -n '3p' "$ROOT_DIR/VERSION" | tr -d '\r')"

          # Backward compatibility: old single-line format.
          if [[ -z "$channel_line" ]]; then
            printf '%s\n' "$base_line"
          elif [[ "$channel_line" == "stable" ]]; then
            printf '%s\n' "$base_line"
          else
            printf '%s-%s.%s\n' "$base_line" "$channel_line" "$n_line"
          fi
        ''
        ''
          channel_to_write="$CHANNEL"
          n_to_write="''${PRERELEASE_NUM:-1}"
          if [[ "$channel_to_write" == "stable" || -z "$channel_to_write" ]]; then
            channel_to_write="stable"
            n_to_write="0"
          fi
          printf '%s\n%s\n%s\n' "$BASE_VERSION" "$channel_to_write" "$n_to_write" > "$ROOT_DIR/VERSION"
        ''
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
