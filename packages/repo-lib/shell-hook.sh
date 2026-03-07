${pre-commit-check.shellHook}

if [ -t 1 ]; then
  command -v tput >/dev/null 2>&1 && tput clear || printf '\033c'
fi

GREEN=$'\033[1;32m'
CYAN=$'\033[1;36m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[1;34m'
RED=$'\033[1;31m'
MAGENTA=$'\033[1;35m'
WHITE=$'\033[1;37m'
GRAY=$'\033[0;90m'
BOLD=$'\033[1m'
UNDERLINE=$'\033[4m'
RESET=$'\033[0m'

repo_lib_probe_tool() {
  local name="$1"
  local color_name="$2"
  local required="$3"
  local line_no="$4"
  local group_no="$5"
  local regex="$6"
  local executable="$7"
  shift 7

  local color="${!color_name:-$YELLOW}"
  local output=""
  local selected=""
  local version=""

  if ! output="$("$executable" "$@" 2>&1)"; then
    printf "  $CYAN %-@TOOL_LABEL_WIDTH@s$RESET $RED%s$RESET\n" "${name}:" "probe failed"
    printf "%s\n" "$output" >&2
    if [ "$required" = "1" ]; then
      exit 1
    fi
    return 0
  fi

  selected="$(printf '%s\n' "$output" | sed -n "${line_no}p")"
  selected="$(printf '%s' "$selected" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

  if [ -n "$regex" ]; then
    if [[ "$selected" =~ $regex ]]; then
      version="${BASH_REMATCH[$group_no]}"
    else
      printf "  $CYAN %-@TOOL_LABEL_WIDTH@s$RESET $RED%s$RESET\n" "${name}:" "version parse failed"
      printf "%s\n" "$output" >&2
      if [ "$required" = "1" ]; then
        exit 1
      fi
      return 0
    fi
  else
    version="$selected"
  fi

  if [ -z "$version" ]; then
    printf "  $CYAN %-@TOOL_LABEL_WIDTH@s$RESET $RED%s$RESET\n" "${name}:" "empty version"
    printf "%s\n" "$output" >&2
    if [ "$required" = "1" ]; then
      exit 1
    fi
    return 0
  fi

  printf "  $CYAN %-@TOOL_LABEL_WIDTH@s$RESET %s%s$RESET\n" "${name}:" "$color" "$version"
}

repo_lib_probe_legacy_tool() {
  local name="$1"
  local color_name="$2"
  local required="$3"
  local command_name="$4"
  local version_command="$5"

  local color="${!color_name:-$YELLOW}"
  local output=""
  local version=""

  if ! command -v "$command_name" >/dev/null 2>&1; then
    if [ "$required" = "1" ]; then
      printf "  $CYAN %-@TOOL_LABEL_WIDTH@s$RESET $RED%s$RESET\n" "${name}:" "missing command"
      exit 1
    fi
    return 0
  fi

  if ! output="$(sh -c "$command_name $version_command" 2>&1)"; then
    printf "  $CYAN %-@TOOL_LABEL_WIDTH@s$RESET $RED%s$RESET\n" "${name}:" "probe failed"
    printf "%s\n" "$output" >&2
    if [ "$required" = "1" ]; then
      exit 1
    fi
    return 0
  fi

  version="$(printf '%s\n' "$output" | head -n 1 | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  if [ -z "$version" ]; then
    printf "  $CYAN %-@TOOL_LABEL_WIDTH@s$RESET $RED%s$RESET\n" "${name}:" "empty version"
    printf "%s\n" "$output" >&2
    if [ "$required" = "1" ]; then
      exit 1
    fi
    return 0
  fi

  printf "  $CYAN %-@TOOL_LABEL_WIDTH@s$RESET %s%s$RESET\n" "${name}:" "$color" "$version"
}

@SHELL_ENV_SCRIPT@

@BOOTSTRAP@

printf "\n$GREEN 🚀 Dev shell ready$RESET\n\n"
@TOOL_BANNER_SCRIPT@
printf "\n"

@EXTRA_SHELL_TEXT@
