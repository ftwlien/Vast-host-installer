#!/usr/bin/env bash
set -euo pipefail

install_nvidia_placeholder() {
  if ! is_apt_system; then
    die "NVIDIA install module currently supports apt-based Ubuntu/Debian systems only"
  fi
  log "placeholder: install NVIDIA driver stack (default target currently planned as nvidia-driver-595-open or policy-driven variant)"
}

install_nvidia_590_open_from_known_good_flow() {
  if ! is_apt_system; then
    die "NVIDIA install module currently supports apt-based Ubuntu/Debian systems only"
  fi
  log "installing NVIDIA using known-good onboarding flow (590-open baseline)"
  sudo apt update
  sudo apt install -y software-properties-common ubuntu-drivers-common build-essential
  sudo apt purge -y 'nvidia-*' || true
  sudo apt autoremove -y || true

  if ! sudo ubuntu-drivers install nvidia:590-open && ! sudo apt install -y nvidia-driver-590-open; then
    warn "Ubuntu-native NVIDIA install path failed; trying graphics-drivers PPA fallback"
    sudo add-apt-repository ppa:graphics-drivers/ppa -y
    sudo apt update
    sudo ubuntu-drivers install nvidia:590-open || sudo apt install -y nvidia-driver-590-open
  fi
  sudo nvidia-xconfig -a --cool-bits=28 --allow-empty-initial-configuration --enable-all-gpus || true
  sudo bash -c '(crontab -l 2>/dev/null; echo "@reboot nvidia-smi -pm 1" ) | crontab -'
}

verify_nvidia_ready_or_die() {
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    die "NVIDIA driver install did not provide nvidia-smi. Refusing to continue to Vast setup."
  fi
  if ! nvidia-smi >/dev/null 2>&1; then
    die "nvidia-smi failed. NVIDIA is not ready, so Vast setup will not continue."
  fi
  success "NVIDIA looks ready (nvidia-smi works)."
}
