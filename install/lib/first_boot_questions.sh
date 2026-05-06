#!/usr/bin/env bash
set -euo pipefail

FIRST_BOOT_INSTALL_VAST_CLI=0
FIRST_BOOT_INSTALL_RIG_MONITOR=0
FIRST_BOOT_INSTALL_FLEET_HEALTH=0
FIRST_BOOT_HOSTNAME=""
FIRST_BOOT_VAST_INSTALL_COMMAND=""
FIRST_BOOT_USERNAME=""
FIRST_BOOT_PASSWORD=""

prompt_yes_no() {
  local prompt default reply
  prompt="$1"
  default="$2"
  read -r -p "$prompt [$default]: " reply
  reply="${reply:-$default}"
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

prompt_password_twice() {
  local p1 p2
  while true; do
    read -r -s -p "Password: " p1
    echo
    read -r -s -p "Confirm password: " p2
    echo
    if [[ -z "$p1" ]]; then
      warn "Password cannot be empty."
      continue
    fi
    if [[ "$p1" != "$p2" ]]; then
      warn "Passwords did not match. Try again."
      continue
    fi
    FIRST_BOOT_PASSWORD="$p1"
    return 0
  done
}

run_first_boot_questionnaire() {
  clear_terminal
  hero_banner
  banner "First Run Setup"
  step "Answer once. After each reboot, log in and run the shown command."

  question "1/3 Machine identity"
  read -r -p "Final hostname for this rig: " FIRST_BOOT_HOSTNAME
  [[ -n "$FIRST_BOOT_HOSTNAME" ]] || die "Hostname is required"

  read -r -p "Final operator username: " FIRST_BOOT_USERNAME
  [[ -n "$FIRST_BOOT_USERNAME" ]] || die "Final username is required"
  prompt_password_twice

  question "2/3 Vast bootstrap"
  prompt_box "Paste the full Vast.ai install command for this host."
  read -r -p "Vast install command: " FIRST_BOOT_VAST_INSTALL_COMMAND
  [[ -n "$FIRST_BOOT_VAST_INSTALL_COMMAND" ]] || die "Vast install command is required"

  question "3/3 Optional extras"
  if prompt_yes_no "Install Vast CLI locally?" "y"; then
    FIRST_BOOT_INSTALL_VAST_CLI=1
  fi
  if prompt_yes_no "Install rig-monitor for local GPU/host checks?" "y"; then
    FIRST_BOOT_INSTALL_RIG_MONITOR=1
  fi
  if prompt_yes_no "Install Fleet Health Check prerequisites?" "n"; then
    FIRST_BOOT_INSTALL_FLEET_HEALTH=1
  fi
}

emit_first_boot_answers() {
  echo "FIRST_BOOT_HOSTNAME=$FIRST_BOOT_HOSTNAME"
  echo "FIRST_BOOT_INSTALL_VAST_CLI=$FIRST_BOOT_INSTALL_VAST_CLI"
  echo "FIRST_BOOT_INSTALL_RIG_MONITOR=$FIRST_BOOT_INSTALL_RIG_MONITOR"
  echo "FIRST_BOOT_INSTALL_FLEET_HEALTH=$FIRST_BOOT_INSTALL_FLEET_HEALTH"
  echo "FIRST_BOOT_USERNAME=$FIRST_BOOT_USERNAME"
}
