#!/usr/bin/env bash
set -euo pipefail

if [[ -t 1 ]]; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_BLUE='\033[1;34m'
  C_GREEN='\033[1;32m'
  C_YELLOW='\033[1;33m'
  C_RED='\033[1;31m'
  C_CYAN='\033[1;36m'
else
  C_RESET=''
  C_BOLD=''
  C_BLUE=''
  C_GREEN=''
  C_YELLOW=''
  C_RED=''
  C_CYAN=''
fi

banner() {
  printf '\n%b=== %s ===%b\n' "$C_BLUE$C_BOLD" "$*" "$C_RESET"
}

command_box() {
  printf '\n%bCOPY / RUN THIS NEXT:%b\n' "$C_GREEN$C_BOLD" "$C_RESET"
  printf '%b%s%b\n\n' "$C_GREEN$C_BOLD" "$1" "$C_RESET"
}

step() {
  printf '%b→ %s%b\n' "$C_CYAN$C_BOLD" "$*" "$C_RESET"
}

success() {
  printf '%b✓ %s%b\n' "$C_GREEN$C_BOLD" "$*" "$C_RESET"
}

log() {
  printf '%b[vast-host-installer]%b %s\n' "$C_CYAN$C_BOLD" "$C_RESET" "$*"
}

warn() {
  printf '%b[vast-host-installer][warn]%b %s\n' "$C_YELLOW$C_BOLD" "$C_RESET" "$*" >&2
}

die() {
  printf '%b[vast-host-installer][error]%b %s\n' "$C_RED$C_BOLD" "$C_RESET" "$*" >&2
  exit 1
}

prompt_box() {
  printf '\n%b%s%b\n' "$C_YELLOW$C_BOLD" "$1" "$C_RESET"
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
