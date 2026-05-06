#!/usr/bin/env bash
set -euo pipefail

FIRST_BOOT_INSTALL_VAST_CLI=0
FIRST_BOOT_INSTALL_RIG_MONITOR=0
FIRST_BOOT_INSTALL_FLEET_HEALTH=0
FIRST_BOOT_INSTALL_GPU_FAN_CONTROL=0
FIRST_BOOT_INSTALL_GPU_BURN=0
FIRST_BOOT_INSTALL_CPU_BURN=0
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

  question "6/6 Optional extra choices"
  echo "Adds the local Vast CLI command for API checks and self-tests."
  if prompt_yes_no "Install Vast CLI locally?" "y"; then
    FIRST_BOOT_INSTALL_VAST_CLI=1
  fi
  echo "Adds the clean terminal dashboard for GPU temps, fans, power, VRAM and host stats."
  if prompt_yes_no "Install rig-monitor for local GPU/host checks?" "y"; then
    FIRST_BOOT_INSTALL_RIG_MONITOR=1
  fi
  echo "Adds helper dependencies/permissions for later fleet diagnostics."
  if prompt_yes_no "Install Fleet Health Check prerequisites?" "n"; then
    FIRST_BOOT_INSTALL_FLEET_HEALTH=1
  fi
  echo "Adds reboot-safe NVIDIA Xorg + fan services for aggressive Vast.ai cooling."
  if prompt_yes_no "Install aggressive Vast.ai GPU fan control?" "y"; then
    FIRST_BOOT_INSTALL_GPU_FAN_CONTROL=1
  fi
  echo "Builds gpu-burn so you can stress-test all GPUs after setup."
  if prompt_yes_no "Install gpu-burn stress-test tool?" "y"; then
    FIRST_BOOT_INSTALL_GPU_BURN=1
  fi
  echo "Installs stress-ng, memtester, Memtest86+ and cpu_burn for CPU/RAM burn-in tests. Readiness tools are installed automatically."
  if prompt_yes_no "Install CPU/RAM burn stress-test tools?" "y"; then
    FIRST_BOOT_INSTALL_CPU_BURN=1
  fi
}

run_optional_extras_questionnaire() {
  clear_terminal
  hero_banner
  banner "Optional Extras Installer"
  step "Choose only the extras you want to install or repair. No storage, user, hostname, NVIDIA driver, or Vast bootstrap changes will be made."

  question "6/6 Optional extra choices"
  echo "Adds the local Vast CLI command for API checks and self-tests."
  if prompt_yes_no "Install Vast CLI locally?" "n"; then
    FIRST_BOOT_INSTALL_VAST_CLI=1
  fi
  echo "Adds the clean terminal dashboard for GPU temps, fans, power, VRAM and host stats."
  if prompt_yes_no "Install rig-monitor for local GPU/host checks?" "n"; then
    FIRST_BOOT_INSTALL_RIG_MONITOR=1
  fi
  echo "Adds helper dependencies/permissions for later fleet diagnostics."
  if prompt_yes_no "Install Fleet Health Check prerequisites?" "n"; then
    FIRST_BOOT_INSTALL_FLEET_HEALTH=1
  fi
  echo "Adds reboot-safe NVIDIA Xorg + fan services for aggressive Vast.ai cooling."
  if prompt_yes_no "Install aggressive Vast.ai GPU fan control?" "n"; then
    FIRST_BOOT_INSTALL_GPU_FAN_CONTROL=1
  fi
  echo "Builds gpu-burn so you can stress-test all GPUs after setup."
  if prompt_yes_no "Install gpu-burn stress-test tool?" "n"; then
    FIRST_BOOT_INSTALL_GPU_BURN=1
  fi
  echo "Installs stress-ng, memtester, Memtest86+ and cpu_burn for CPU/RAM burn-in tests. Readiness tools are installed automatically."
  if prompt_yes_no "Install CPU/RAM burn stress-test tools?" "n"; then
    FIRST_BOOT_INSTALL_CPU_BURN=1
  fi
}

emit_first_boot_answers() {
  echo "FIRST_BOOT_HOSTNAME=$FIRST_BOOT_HOSTNAME"
  echo "FIRST_BOOT_INSTALL_VAST_CLI=$FIRST_BOOT_INSTALL_VAST_CLI"
  echo "FIRST_BOOT_INSTALL_RIG_MONITOR=$FIRST_BOOT_INSTALL_RIG_MONITOR"
  echo "FIRST_BOOT_INSTALL_FLEET_HEALTH=$FIRST_BOOT_INSTALL_FLEET_HEALTH"
  echo "FIRST_BOOT_INSTALL_GPU_FAN_CONTROL=$FIRST_BOOT_INSTALL_GPU_FAN_CONTROL"
  echo "FIRST_BOOT_INSTALL_GPU_BURN=$FIRST_BOOT_INSTALL_GPU_BURN"
  echo "FIRST_BOOT_INSTALL_CPU_BURN=$FIRST_BOOT_INSTALL_CPU_BURN"
  echo "FIRST_BOOT_USERNAME=$FIRST_BOOT_USERNAME"
}
