#!/usr/bin/env bash
set -euo pipefail

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
  banner "Vast Host Installer - First Run Setup"
  step "We will ask a few simple questions, then prepare the machine in phases."

  read -r -p "Final hostname: " FIRST_BOOT_HOSTNAME
  [[ -n "$FIRST_BOOT_HOSTNAME" ]] || die "Hostname is required"

  read -r -p "Final operator username: " FIRST_BOOT_USERNAME
  [[ -n "$FIRST_BOOT_USERNAME" ]] || die "Final username is required"
  prompt_password_twice

  prompt_box "Paste the full Vast install command from Vast.ai below (for example the wget/python command)."
  read -r -p "Vast install command: " FIRST_BOOT_VAST_INSTALL_COMMAND
  [[ -n "$FIRST_BOOT_VAST_INSTALL_COMMAND" ]] || die "Vast install command is required"

  if prompt_yes_no "Install rig-monitor (includes GPU temp helper setup)?" "y"; then
    FIRST_BOOT_INSTALL_RIG_MONITOR=1
  fi
  if prompt_yes_no "Install fleet-health prereqs?" "n"; then
    FIRST_BOOT_INSTALL_FLEET_HEALTH=1
  fi
}

emit_first_boot_answers() {
  echo "FIRST_BOOT_HOSTNAME=$FIRST_BOOT_HOSTNAME"
  echo "FIRST_BOOT_INSTALL_RIG_MONITOR=$FIRST_BOOT_INSTALL_RIG_MONITOR"
  echo "FIRST_BOOT_INSTALL_FLEET_HEALTH=$FIRST_BOOT_INSTALL_FLEET_HEALTH"
  echo "FIRST_BOOT_USERNAME=$FIRST_BOOT_USERNAME"
}
