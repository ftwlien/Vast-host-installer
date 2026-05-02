#!/usr/bin/env bash
set -euo pipefail

run_base_system_prep_from_known_good_flow() {
  if ! is_apt_system; then
    die "System prep currently supports apt-based Ubuntu/Debian systems only"
  fi
  log "running known-good base system prep"
  sudo apt update
  sudo apt upgrade -y
  sudo apt dist-upgrade -y
  sudo apt install -y update-manager-core

  sudo apt purge --auto-remove unattended-upgrades -y || true
  sudo systemctl disable apt-daily-upgrade.timer || true
  sudo systemctl mask apt-daily-upgrade.service || true
  sudo systemctl disable apt-daily.timer || true
  sudo systemctl mask apt-daily.service || true

  sudo apt install -y software-properties-common ubuntu-drivers-common xfsprogs curl ca-certificates gnupg nethogs parted
}
