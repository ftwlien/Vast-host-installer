#!/usr/bin/env bash
set -euo pipefail

configure_noninteractive_apt() {
  step "Configuring apt for unattended installer prompts"
  sudo mkdir -p /etc/apt/apt.conf.d /etc/needrestart/conf.d
  sudo tee /etc/apt/apt.conf.d/90vast-host-installer-noninteractive >/dev/null <<'EOF'
Dpkg::Options {
  "--force-confdef";
  "--force-confold";
};
APT::Get::Assume-Yes "true";
APT::Get::Show-Upgraded "true";
EOF
  sudo tee /etc/needrestart/conf.d/90-vast-host-installer.conf >/dev/null <<'EOF'
# Managed by vast-host-installer: avoid interactive whiptail dialogs during setup.
$nrconf{restart} = 'a';
$nrconf{kernelhints} = 0;
$nrconf{ucodehints} = 0;
EOF
}

apt_noninteractive() {
  sudo env \
    DEBIAN_FRONTEND=noninteractive \
    NEEDRESTART_MODE=a \
    NEEDRESTART_SUSPEND=1 \
    apt-get \
      -o Dpkg::Options::=--force-confdef \
      -o Dpkg::Options::=--force-confold \
      "$@"
}

run_base_system_prep_from_known_good_flow() {
  if ! is_apt_system; then
    die "System prep currently supports apt-based Ubuntu/Debian systems only"
  fi
  log "running known-good base system prep"
  configure_noninteractive_apt
  apt_noninteractive update
  apt_noninteractive upgrade -y
  apt_noninteractive dist-upgrade -y
  apt_noninteractive install -y update-manager-core

  apt_noninteractive purge --auto-remove unattended-upgrades -y || true
  sudo systemctl disable apt-daily-upgrade.timer || true
  sudo systemctl mask apt-daily-upgrade.service || true
  sudo systemctl disable apt-daily.timer || true
  sudo systemctl mask apt-daily.service || true

  apt_noninteractive install -y software-properties-common ubuntu-drivers-common xfsprogs curl ca-certificates gnupg nethogs parted
}
