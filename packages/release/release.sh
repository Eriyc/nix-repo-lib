#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
GITLINT_FILE="$ROOT_DIR/.gitlint"
START_HEAD=""
CREATED_TAG=""

# ── logging ────────────────────────────────────────────────────────────────

log() { echo "[release] $*" >&2; }

usage() {
  local cmd
  cmd="$(basename "$0")"
  printf '%s\n' \
    "Usage:" \
    "  ${cmd} [major|minor|patch] [stable|__CHANNEL_LIST__]" \
    "  ${cmd} set <version>" \
    "" \
    "Bump types:" \
    "  (none)            bump patch, keep current channel" \
    "  major/minor/patch bump the given part, keep current channel" \
    "  stable / full     remove prerelease suffix" \
    "  __CHANNEL_LIST__    switch channel (bumps prerelease number if same base+channel)" \
    "" \
    "Examples:" \
    "  ${cmd}                 # patch bump on current channel" \
    "  ${cmd} minor           # minor bump on current channel" \
    "  ${cmd} patch beta      # patch bump, switch to beta channel" \
    "  ${cmd} rc              # switch to rc channel" \
    "  ${cmd} stable          # promote to stable release" \
    "  ${cmd} set 1.2.3" \
    "  ${cmd} set 1.2.3-beta.1"
}

# ── git ────────────────────────────────────────────────────────────────────

require_clean_git() {
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: git working tree is not clean. Commit or stash changes first." >&2
    exit 1
  fi
}

revert_on_failure() {
  local status=$?
  if [[ -n $START_HEAD ]]; then
    log "Release failed — reverting to $START_HEAD"
    git reset --hard "$START_HEAD"
  fi
  if [[ -n $CREATED_TAG ]]; then
    git tag -d "$CREATED_TAG" >/dev/null 2>&1 || true
  fi
  exit $status
}

# ── version parsing ────────────────────────────────────────────────────────

parse_base_version() {
  local v="$1"
  if [[ ! $v =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Error: invalid base version '$v' (expected x.y.z)" >&2
    exit 1
  fi
  MAJOR="${BASH_REMATCH[1]}"
  MINOR="${BASH_REMATCH[2]}"
  PATCH="${BASH_REMATCH[3]}"
}

parse_full_version() {
  local v="$1"
  CHANNEL="stable"
  PRERELEASE_NUM=""

  if [[ $v =~ ^([0-9]+\.[0-9]+\.[0-9]+)-([a-zA-Z]+)\.([0-9]+)$ ]]; then
    BASE_VERSION="${BASH_REMATCH[1]}"
    CHANNEL="${BASH_REMATCH[2]}"
    PRERELEASE_NUM="${BASH_REMATCH[3]}"
  elif [[ $v =~ ^([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    BASE_VERSION="${BASH_REMATCH[1]}"
  else
    echo "Error: invalid version '$v' (expected x.y.z or x.y.z-channel.N)" >&2
    exit 1
  fi
  parse_base_version "$BASE_VERSION"
}

validate_channel() {
  local ch="$1"
  [[ $ch == "stable" ]] && return 0
  local valid_channels="__CHANNEL_LIST__"
  for c in $valid_channels; do
    [[ $ch == "$c" ]] && return 0
  done
  echo "Error: unknown channel '$ch'. Valid channels: stable $valid_channels" >&2
  exit 1
}

version_cmp() {
  # Returns: 0 if equal, 1 if v1 > v2, 2 if v1 < v2
  # Stable > prerelease for same base version
  local v1="$1" v2="$2"
  [[ $v1 == "$v2" ]] && return 0

  local base1="" pre1="" base2="" pre2=""
  if [[ $v1 =~ ^([0-9]+\.[0-9]+\.[0-9]+)-(.+)$ ]]; then
    base1="${BASH_REMATCH[1]}"
    pre1="${BASH_REMATCH[2]}"
  else
    base1="$v1"
  fi
  if [[ $v2 =~ ^([0-9]+\.[0-9]+\.[0-9]+)-(.+)$ ]]; then
    base2="${BASH_REMATCH[1]}"
    pre2="${BASH_REMATCH[2]}"
  else
    base2="$v2"
  fi

  if [[ $base1 != "$base2" ]]; then
    local highest_base
    highest_base=$(printf '%s\n%s\n' "$base1" "$base2" | sort -V | tail -n1)
    [[ $highest_base == "$base1" ]] && return 1 || return 2
  fi

  [[ -z $pre1 && -n $pre2 ]] && return 1 # stable > prerelease
  [[ -n $pre1 && -z $pre2 ]] && return 2 # prerelease < stable
  [[ -z $pre1 && -z $pre2 ]] && return 0 # both stable

  local highest_pre
  highest_pre=$(printf '%s\n%s\n' "$pre1" "$pre2" | sort -V | tail -n1)
  [[ $highest_pre == "$pre1" ]] && return 1 || return 2
}

bump_base_version() {
  case "$1" in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch) PATCH=$((PATCH + 1)) ;;
  *)
    echo "Error: unknown bump part '$1'" >&2
    exit 1
    ;;
  esac
  BASE_VERSION="${MAJOR}.${MINOR}.${PATCH}"
}

compute_full_version() {
  if [[ $CHANNEL == "stable" || -z $CHANNEL ]]; then
    FULL_VERSION="$BASE_VERSION"
  else
    FULL_VERSION="${BASE_VERSION}-${CHANNEL}.${PRERELEASE_NUM:-1}"
  fi
  export BASE_VERSION CHANNEL PRERELEASE_NUM FULL_VERSION
}

# ── gitlint ────────────────────────────────────────────────────────────────

get_gitlint_title_regex() {
  [[ ! -f $GITLINT_FILE ]] && return 0
  awk '
    /^\[title-match-regex\]$/ { in_section=1; next }
    /^\[/ { in_section=0 }
    in_section && /^regex=/ { sub(/^regex=/, ""); print; exit }
  ' "$GITLINT_FILE"
}

validate_commit_message() {
  local msg="$1"
  local regex
  regex="$(get_gitlint_title_regex)"
  if [[ -n $regex && ! $msg =~ $regex ]]; then
    echo "Error: commit message does not match .gitlint title-match-regex" >&2
    echo "Regex:   $regex" >&2
    echo "Message: $msg" >&2
    exit 1
  fi
}

# ── version file generation ────────────────────────────────────────────────

generate_version_files() {
  :
  __VERSION_FILES__
}

# ── version source (built-in) ──────────────────────────────────────────────

do_read_version() {
  if [[ ! -f "$ROOT_DIR/VERSION" ]]; then
    local highest_tag=""
    while IFS= read -r raw_tag; do
      local tag="${raw_tag#v}"
      [[ $tag =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z]+\.[0-9]+)?$ ]] || continue

      if [[ -z $highest_tag ]]; then
        highest_tag="$tag"
        continue
      fi

      local cmp_status=0
      version_cmp "$tag" "$highest_tag" || cmp_status=$?
      [[ $cmp_status -eq 1 ]] && highest_tag="$tag"
    done < <(git tag --list)

    [[ -z $highest_tag ]] && highest_tag="0.0.1"

    parse_full_version "$highest_tag"
    local channel_to_write="$CHANNEL"
    local n_to_write="${PRERELEASE_NUM:-1}"
    if [[ $channel_to_write == "stable" || -z $channel_to_write ]]; then
      channel_to_write="stable"
      n_to_write="0"
    fi

    printf '%s\n%s\n%s\n' "$BASE_VERSION" "$channel_to_write" "$n_to_write" > "$ROOT_DIR/VERSION"
    log "Initialized $ROOT_DIR/VERSION from highest tag: v$highest_tag"
  fi

  local base_line channel_line n_line
  base_line="$(sed -n '1p' "$ROOT_DIR/VERSION" | tr -d '\r')"
  channel_line="$(sed -n '2p' "$ROOT_DIR/VERSION" | tr -d '\r')"
  n_line="$(sed -n '3p' "$ROOT_DIR/VERSION" | tr -d '\r')"

  if [[ -z $channel_line ]]; then
    printf '%s\n' "$base_line"
  elif [[ $channel_line == "stable" ]]; then
    printf '%s\n' "$base_line"
  else
    printf '%s-%s.%s\n' "$base_line" "$channel_line" "$n_line"
  fi
}

do_write_version() {
  local channel_to_write="$CHANNEL"
  local n_to_write="${PRERELEASE_NUM:-1}"
  if [[ $channel_to_write == "stable" || -z $channel_to_write ]]; then
    channel_to_write="stable"
    n_to_write="0"
  fi
  printf '%s\n%s\n%s\n' "$BASE_VERSION" "$channel_to_write" "$n_to_write" > "$ROOT_DIR/VERSION"
}

# ── user-provided hook ─────────────────────────────────────────────────────

do_post_version() {
  :
  __POST_VERSION__
}

# ── main ───────────────────────────────────────────────────────────────────

main() {
  [[ ${1-} == "-h" || ${1-} == "--help" ]] && usage && exit 0

  require_clean_git
  START_HEAD="$(git rev-parse HEAD)"
  trap revert_on_failure ERR

  local raw_version
  raw_version="$(do_read_version)"
  parse_full_version "$raw_version"

  log "Current: base=$BASE_VERSION channel=$CHANNEL pre=${PRERELEASE_NUM:-}"

  local action="${1-}"
  shift || true

  if [[ $action == "set" ]]; then
    local newv="${1-}"
    [[ -z $newv ]] && echo "Error: 'set' requires a version argument" >&2 && exit 1
    compute_full_version
    local current_full="$FULL_VERSION"
    parse_full_version "$newv"
    validate_channel "$CHANNEL"
    compute_full_version
    local cmp_status=0
    version_cmp "$FULL_VERSION" "$current_full" || cmp_status=$?
    case $cmp_status in
    0)
      echo "Version $FULL_VERSION is already current; nothing to do." >&2
      exit 1
      ;;
    2)
      echo "Error: $FULL_VERSION is lower than current $current_full" >&2
      exit 1
      ;;
    esac

  else
    local part="" target_channel=""

    case "$action" in
    "") part="patch" ;;
    major | minor | patch)
      part="$action"
      target_channel="${1-}"
      ;;
    stable | full)
      [[ -n ${1-} ]] && echo "Error: '$action' takes no second argument" >&2 && usage && exit 1
      target_channel="stable"
      ;;
    *)
      # check if action is a valid channel
      local is_channel=0
      for c in __CHANNEL_LIST__; do
        [[ $action == "$c" ]] && is_channel=1 && break
      done
      if [[ $is_channel == 1 ]]; then
        [[ -n ${1-} ]] && echo "Error: channel-only bump takes no second argument" >&2 && usage && exit 1
        target_channel="$action"
      else
        echo "Error: unknown argument '$action'" >&2
        usage
        exit 1
      fi
      ;;
    esac

    [[ -z $target_channel ]] && target_channel="$CHANNEL"
    [[ $target_channel == "full" ]] && target_channel="stable"
    validate_channel "$target_channel"

    local old_base="$BASE_VERSION" old_channel="$CHANNEL" old_pre="$PRERELEASE_NUM"
    [[ -n $part ]] && bump_base_version "$part"

    if [[ $target_channel == "stable" ]]; then
      CHANNEL="stable"
      PRERELEASE_NUM=""
    else
      if [[ $BASE_VERSION == "$old_base" && $target_channel == "$old_channel" && -n $old_pre ]]; then
        PRERELEASE_NUM=$((old_pre + 1))
      else
        PRERELEASE_NUM=1
      fi
      CHANNEL="$target_channel"
    fi
  fi

  compute_full_version
  log "Releasing $FULL_VERSION"

  do_write_version
  log "Updated version source"

  generate_version_files

  do_post_version
  log "Post-version hook done"

  (cd "$ROOT_DIR" && nix fmt)
  log "Formatted files"

  git add -A
  local commit_msg="chore(release): v$FULL_VERSION"
  validate_commit_message "$commit_msg"
  git commit -m "$commit_msg"
  log "Created commit"

  git tag "v$FULL_VERSION"
  CREATED_TAG="v$FULL_VERSION"
  log "Tagged v$FULL_VERSION"

  git push
  git push --tags
  log "Done — released v$FULL_VERSION"

  trap - ERR
}

main "$@"
