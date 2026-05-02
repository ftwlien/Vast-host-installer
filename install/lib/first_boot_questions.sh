#!/usr/bin/env bash
set -euo pipefail

FIRST_BOOT_INSTALL_RIG_MONITOR=0
FIRST_BOOT_INSTALL_GPUTEMPS=0
FIRST_BOOT_INSTALL_FLEET_HEALTH=0
FIRST_BOOT_HOSTNAME=""
FIRST_BOOT_API_KEY=""
FIRST_BOOT_USERNAME=""
FIRST_BOOT_PASSWORD=""
FIRST_BOOT_PORT_RANGE="40000-40019"

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
      echo "Password cannot be empty."
      continue
    fi
    if [[ "$p1" != "$p2" ]]; then
      echo "Passwords did not match. Try again."
      continue
    fi
    FIRST_BOOT_PASSWORD="$p1"
    return 0
  done
}

run_first_boot_questionnaire() {
  echo "== Vast Host Installer first-run setup =="

  read -r -p "Final hostname: " FIRST_BOOT_HOSTNAME
  [[ -n "$FIRST_BOOT_HOSTNAME" ]] || die "Hostname is required"

  read -r -s -p "Vast API key: " FIRST_BOOT_API_KEY
  echo
  [[ -n "$FIRST_BOOT_API_KEY" ]] || die "Vast API key is required"

  read -r -p "Vast host port range [40000-40019]: " FIRST_BOOT_PORT_RANGE
  FIRST_BOOT_PORT_RANGE="${FIRST_BOOT_PORT_RANGE:-40000-40019}"

  if prompt_yes_no "Create/set final operator user?" "y"; then
    read -r -p "Final username: " FIRST_BOOT_USERNAME
    [[ -n "$FIRST_BOOT_USERNAME" ]] || die "Username is required when creating final operator user"
    prompt_password_twice
  fi

  if prompt_yes_no "Install rig-monitor?" "y"; then
    FIRST_BOOT_INSTALL_RIG_MONITOR=1
  fi
  if prompt_yes_no "Install gputemps?" "y"; then
    FIRST_BOOT_INSTALL_GPUTEMPS=1
  fi
  if prompt_yes_no "Install fleet-health prereqs?" "n"; then
    FIRST_BOOT_INSTALL_FLEET_HEALTH=1
  fi
}

emit_first_boot_answers() {
  echo "FIRST_BOOT_HOSTNAME=$FIRST_BOOT_HOSTNAME"
  echo "FIRST_BOOT_INSTALL_RIG_MONITOR=$FIRST_BOOT_INSTALL_RIG_MONITOR"
  echo "FIRST_BOOT_INSTALL_GPUTEMPS=$FIRST_BOOT_INSTALL_GPUTEMPS"
  echo "FIRST_BOOT_INSTALL_FLEET_HEALTH=$FIRST_BOOT_INSTALL_FLEET_HEALTH"
  echo "FIRST_BOOT_USERNAME=$FIRST_BOOT_USERNAME"
  echo "FIRST_BOOT_PORT_RANGE=$FIRST_BOOT_PORT_RANGE"
}
