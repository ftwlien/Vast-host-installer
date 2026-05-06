#!/usr/bin/env bash
set -euo pipefail

if [[ -t 1 ]]; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_DIM='\033[2m'
  C_BLUE='\033[1;34m'
  C_GREEN='\033[1;32m'
  C_YELLOW='\033[1;33m'
  C_RED='\033[1;31m'
  C_CYAN='\033[1;36m'
  C_MAGENTA='\033[1;35m'
  C_PURPLE='\033[1;38;5;45m'
  C_SKY='\033[1;38;5;45m'
  C_ORANGE='\033[1;38;5;214m'
  C_GRAY='\033[1;38;5;244m'
else
  C_RESET=''
  C_BOLD=''
  C_DIM=''
  C_BLUE=''
  C_GREEN=''
  C_YELLOW=''
  C_RED=''
  C_CYAN=''
  C_MAGENTA=''
  C_PURPLE=''
  C_SKY=''
  C_ORANGE=''
  C_GRAY=''
fi

_box_line() {
  local char count out
  char="$1"
  count="$2"
  out=""
  while [[ ${#out} -lt "$count" ]]; do
    out+="$char"
  done
  printf '%s' "$out"
}

_print_rule() {
  printf '%b%s%b\n' "$C_GRAY" "$(_box_line '─' 72)" "$C_RESET"
}

_print_box_text() {
  local color="$1" text="$2" width=70 line
  while [[ -n "$text" ]]; do
    line="${text:0:$width}"
    text="${text:$width}"
    printf '%b│%b %-70s %b│%b\n' "$color" "$C_RESET" "$line" "$color" "$C_RESET"
  done
}

banner() {
  local title="$*" width=72 pad
  pad=$(( width - ${#title} ))
  (( pad < 0 )) && pad=0
  printf '\n%b╭─ %b%s%b %b%s╮%b\n' "$C_SKY$C_BOLD" "$C_RESET" "$title" "$C_SKY$C_BOLD" "$(_box_line '─' "$pad")" "$C_SKY$C_BOLD" "$C_RESET"
  printf '%b╰%s╯%b\n' "$C_SKY$C_BOLD" "$(_box_line '─' "$width")" "$C_RESET"
}

success_banner() {
  local title="$*"
  local width=84
  local left right
  left=$(( (width - ${#title}) / 2 ))
  right=$(( width - left - ${#title} ))
  printf '\n%b╭%s╮%b\n' "$C_GREEN$C_BOLD" "$(_box_line '═' "$width")" "$C_RESET"
  printf '%b│%*s│%b\n' "$C_GREEN$C_BOLD" "$width" "" "$C_RESET"
  printf '%b│%b%*s%b%s%b%*s%b│%b\n' "$C_GREEN$C_BOLD" "$C_RESET" "$left" "" "$C_GREEN$C_BOLD" "$title" "$C_RESET" "$right" "" "$C_GREEN$C_BOLD" "$C_RESET"
  printf '%b│%*s│%b\n' "$C_GREEN$C_BOLD" "$width" "" "$C_RESET"
  printf '%b╰%s╯%b\n' "$C_GREEN$C_BOLD" "$(_box_line '═' "$width")" "$C_RESET"
}

hero_banner() {
  printf '\n%b' "$C_SKY$C_BOLD"
  cat <<'EOF'
██╗   ██╗ █████╗ ███████╗████████╗    ██╗  ██╗ ██████╗ ███████╗████████╗
██║   ██║██╔══██╗██╔════╝╚══██╔══╝    ██║  ██║██╔═══██╗██╔════╝╚══██╔══╝
██║   ██║███████║███████╗   ██║       ███████║██║   ██║███████╗   ██║
╚██╗ ██╔╝██╔══██║╚════██║   ██║       ██╔══██║██║   ██║╚════██║   ██║
 ╚████╔╝ ██║  ██║███████║   ██║       ██║  ██║╚██████╔╝███████║   ██║
  ╚═══╝  ╚═╝  ╚═╝╚══════╝   ╚═╝       ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝
EOF
  printf '%b' "$C_RESET"
  printf '%bFast RAM ISO · Ubuntu 22.04 · NVIDIA Open Driver · Vast.ai Host Setup%b\n\n' "$C_SKY$C_BOLD" "$C_RESET"
}
clear_terminal() {
  if [[ -t 1 ]]; then
    printf '\033[H\033[2J\033[3J'
  fi
}

command_box() {
  local cmd="$1"
  printf '\n%b╭─ NEXT COMMAND ─────────────────────────────────────────────────────╮%b\n' "$C_GREEN$C_BOLD" "$C_RESET"
  printf '%b│%b %b%-66.66s%b %b│%b\n' "$C_GREEN$C_BOLD" "$C_RESET" "$C_GREEN$C_BOLD" "$cmd" "$C_RESET" "$C_GREEN$C_BOLD" "$C_RESET"
  printf '%b╰─────────────────────────────────────────────────────────────────────╯%b\n\n' "$C_GREEN$C_BOLD" "$C_RESET"
}

command_list_box() {
  local line
  printf '\n%b╭─ NEXT COMMANDS ────────────────────────────────────────────────────╮%b\n' "$C_GREEN$C_BOLD" "$C_RESET"
  for line in "$@"; do
    printf '%b│%b %b%-66.66s%b %b│%b\n' "$C_GREEN$C_BOLD" "$C_RESET" "$C_GREEN$C_BOLD" "$line" "$C_RESET" "$C_GREEN$C_BOLD" "$C_RESET"
  done
  printf '%b╰─────────────────────────────────────────────────────────────────────╯%b\n\n' "$C_GREEN$C_BOLD" "$C_RESET"
}

step() {
  printf '\n%b▶%b %b%s%b\n' "$C_SKY$C_BOLD" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"
  printf '%b  %s%b\n' "$C_GRAY" "$(_box_line '·' 70)" "$C_RESET"
}

success() {
  printf '%b✓%b %b%s%b\n' "$C_GREEN$C_BOLD" "$C_RESET" "$C_GREEN$C_BOLD" "$*" "$C_RESET"
}

log() {
  printf '%b[%bVAST%b]%b %s\n' "$C_GRAY" "$C_SKY$C_BOLD" "$C_GRAY" "$C_RESET" "$*"
}

warn() {
  printf '\n%b╭─ WARNING ─────────────────────────────────────────────────────────╮%b\n' "$C_ORANGE$C_BOLD" "$C_RESET" >&2
  _print_box_text "$C_ORANGE$C_BOLD" "$*" >&2
  printf '%b╰─────────────────────────────────────────────────────────────────────╯%b\n' "$C_ORANGE$C_BOLD" "$C_RESET" >&2
}

die() {
  printf '\n%b╭─ INSTALL FAILED ──────────────────────────────────────────────────╮%b\n' "$C_RED$C_BOLD" "$C_RESET" >&2
  _print_box_text "$C_RED$C_BOLD" "$*" >&2
  printf '%b╰─────────────────────────────────────────────────────────────────────╯%b\n' "$C_RED$C_BOLD" "$C_RESET" >&2
  exit 1
}

prompt_box() {
  printf '\n%b╭─ INPUT REQUIRED ─────────────────────────────────────────────────╮%b\n' "$C_ORANGE$C_BOLD" "$C_RESET"
  _print_box_text "$C_ORANGE$C_BOLD" "$1"
  printf '%b╰─────────────────────────────────────────────────────────────────────╯%b\n' "$C_ORANGE$C_BOLD" "$C_RESET"
}

question() {
  printf '\n%b◆%b %b%s%b\n' "$C_ORANGE$C_BOLD" "$C_RESET" "$C_BOLD" "$1" "$C_RESET"
}

summary_box() {
  local title="$1"
  shift
  printf '\n%b╭─ %-64.64s ╮%b\n' "$C_PURPLE$C_BOLD" "$title" "$C_RESET"
  for line in "$@"; do
    printf '%b│%b %b✓%b %-67.67s %b│%b\n' "$C_PURPLE$C_BOLD" "$C_RESET" "$C_GREEN$C_BOLD" "$C_RESET" "$line" "$C_PURPLE$C_BOLD" "$C_RESET"
  done
  printf '%b╰─────────────────────────────────────────────────────────────────────╯%b\n\n' "$C_PURPLE$C_BOLD" "$C_RESET"
}

install_report_box() {
  local title="$1" line chunk prefix color width=84 text_width=78
  shift
  color="$C_SKY$C_BOLD"
  printf '\n%b╭─ %-76.76s ╮%b\n' "$color" "$title" "$C_RESET"
  for line in "$@"; do
    prefix="✓"
    while [[ -n "$line" ]]; do
      chunk="${line:0:$text_width}"
      line="${line:$text_width}"
      printf '%b│%b %b%s%b %-78s %b│%b\n' "$color" "$C_RESET" "$C_GREEN$C_BOLD" "$prefix" "$C_RESET" "$chunk" "$color" "$C_RESET"
      prefix=" "
    done
  done
  printf '%b╰%s╯%b\n\n' "$color" "$(_box_line '─' "$width")" "$C_RESET"
}

prompt_reboot_now() {
  local reply
  read -r -p "Reboot now? [Y/n]: " reply
  reply="${reply:-Y}"
  case "$reply" in
    y|Y|yes|YES|'')
      sudo reboot
      ;;
    *)
      return 0
      ;;
  esac
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

is_apt_system() {
  command -v apt-get >/dev/null 2>&1
}

ensure_basic_tools() {
  require_cmd bash
  require_cmd awk
  require_cmd sed
  require_cmd lsblk
  require_cmd findmnt
  require_cmd python3
}
