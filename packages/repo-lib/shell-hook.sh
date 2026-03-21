@HOOKS_SHELL_HOOK@

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

REPO_LIB_TOOL_VERSION=""
REPO_LIB_TOOL_ERROR=""

repo_lib_capture_tool() {
  local required="$1"
  local line_no="$2"
  local group_no="$3"
  local regex="$4"
  local match_regex="$5"
  local executable="$6"
  shift 6

  local output=""
  local selected=""
  local version=""

  REPO_LIB_TOOL_VERSION=""
  REPO_LIB_TOOL_ERROR=""

  if ! output="$("$executable" "$@" 2>&1)"; then
    REPO_LIB_TOOL_ERROR="probe failed"
    printf "%s\n" "$output" >&2
    return 1
  fi

  if [ -n "$match_regex" ]; then
    selected="$(printf '%s\n' "$output" | grep -E -m 1 "$match_regex" || true)"
  else
    selected="$(printf '%s\n' "$output" | sed -n "${line_no}p")"
  fi
  selected="$(printf '%s' "$selected" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

  if [ -n "$regex" ]; then
    if [[ "$selected" =~ $regex ]]; then
      version="${BASH_REMATCH[$group_no]}"
    else
      REPO_LIB_TOOL_ERROR="version parse failed"
      printf "%s\n" "$output" >&2
      return 1
    fi
  else
    version="$selected"
  fi

  if [ -z "$version" ]; then
    REPO_LIB_TOOL_ERROR="empty version"
    printf "%s\n" "$output" >&2
    return 1
  fi

  REPO_LIB_TOOL_VERSION="$version"
  return 0
}

repo_lib_print_simple_header() {
  local title_color_name="$1"
  local icon="$2"
  local title="$3"
  local subtitle_color_name="$4"
  local subtitle="$5"

  local title_color="${!title_color_name:-$GREEN}"
  local subtitle_color="${!subtitle_color_name:-$GRAY}"

  printf "\n%s" "$title_color"
  if [ -n "$icon" ]; then
    printf "%s " "$icon"
  fi
  printf "%s%s" "$title" "$RESET"
  if [ -n "$subtitle" ]; then
    printf " %s%s%s" "$subtitle_color" "$subtitle" "$RESET"
  fi
  printf "\n\n"
}

repo_lib_print_simple_tool() {
  local name="$1"
  local color_name="$2"
  local icon="$3"
  local icon_color_name="$4"
  local required="$5"
  local line_no="$6"
  local group_no="$7"
  local regex="$8"
  local match_regex="$9"
  local executable="${10}"
  shift 10

  local color="${!color_name:-$YELLOW}"
  local effective_icon_color_name="$icon_color_name"
  local icon_color=""

  if [ -z "$effective_icon_color_name" ]; then
    effective_icon_color_name="$color_name"
  fi

  if repo_lib_capture_tool "$required" "$line_no" "$group_no" "$regex" "$match_regex" "$executable" "$@"; then
    icon_color="${!effective_icon_color_name:-$color}"
    printf "  "
    if [ -n "$icon" ]; then
      printf "%s%s%s " "$icon_color" "$icon" "$RESET"
    fi
    printf "$CYAN %-@TOOL_LABEL_WIDTH@s$RESET %s%s$RESET\n" "${name}:" "$color" "$REPO_LIB_TOOL_VERSION"
  else
    printf "  "
    if [ -n "$icon" ]; then
      printf "%s%s%s " "$RED" "$icon" "$RESET"
    fi
    printf "$CYAN %-@TOOL_LABEL_WIDTH@s$RESET $RED%s$RESET\n" "${name}:" "$REPO_LIB_TOOL_ERROR"
    if [ "$required" = "1" ]; then
      exit 1
    fi
  fi
}

repo_lib_print_pretty_header() {
  local border_color_name="$1"
  local title_color_name="$2"
  local icon="$3"
  local title="$4"
  local subtitle_color_name="$5"
  local subtitle="$6"

  local border_color="${!border_color_name:-$BLUE}"
  local title_color="${!title_color_name:-$GREEN}"
  local subtitle_color="${!subtitle_color_name:-$GRAY}"

  printf "\n%s╭─%s %s" "$border_color" "$RESET" "$title_color"
  if [ -n "$icon" ]; then
    printf "%s " "$icon"
  fi
  printf "%s%s" "$title" "$RESET"
  if [ -n "$subtitle" ]; then
    printf " %s%s%s" "$subtitle_color" "$subtitle" "$RESET"
  fi
  printf "\n"
}

repo_lib_print_pretty_row() {
  local border_color_name="$1"
  local icon="$2"
  local icon_color_name="$3"
  local label="$4"
  local value="$5"
  local value_color_name="$6"

  local border_color="${!border_color_name:-$BLUE}"
  local icon_color="${!icon_color_name:-$WHITE}"
  local value_color="${!value_color_name:-$YELLOW}"

  if [ -z "$icon" ]; then
    icon="•"
  fi

  printf "%s│%s %s%s%s ${WHITE}%-@TOOL_LABEL_WIDTH@s${RESET} %s%s${RESET}\n" \
    "$border_color" "$RESET" "$icon_color" "$icon" "$RESET" "$label" "$value_color" "$value"
}

repo_lib_print_pretty_tool() {
  local border_color_name="$1"
  local name="$2"
  local color_name="$3"
  local icon="$4"
  local icon_color_name="$5"
  local required="$6"
  local line_no="$7"
  local group_no="$8"
  local regex="$9"
  local match_regex="${10}"
  local executable="${11}"
  shift 11

  local effective_icon_color_name="$icon_color_name"
  local value_color_name="$color_name"
  local value=""

  if [ -z "$effective_icon_color_name" ]; then
    effective_icon_color_name="$color_name"
  fi

  if repo_lib_capture_tool "$required" "$line_no" "$group_no" "$regex" "$match_regex" "$executable" "$@"; then
    value="$REPO_LIB_TOOL_VERSION"
  else
    value="$REPO_LIB_TOOL_ERROR"
    effective_icon_color_name="RED"
    value_color_name="RED"
  fi

  repo_lib_print_pretty_row \
    "$border_color_name" \
    "$icon" \
    "$effective_icon_color_name" \
    "$name" \
    "$value" \
    "$value_color_name"

  if [ "$value_color_name" = "RED" ] && [ "$required" = "1" ]; then
    exit 1
  fi
}

repo_lib_print_pretty_footer() {
  local border_color_name="$1"
  local border_color="${!border_color_name:-$BLUE}"

  printf "%s╰─%s\n\n" "$border_color" "$RESET"
}

@SHELL_ENV_SCRIPT@

@BOOTSTRAP@

@SHELL_BANNER_SCRIPT@

@EXTRA_SHELL_TEXT@
