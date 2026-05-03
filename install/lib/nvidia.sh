#!/usr/bin/env bash
set -euo pipefail

install_nvidia_placeholder() {
  if ! is_apt_system; then
    die "NVIDIA install module currently supports apt-based Ubuntu/Debian systems only"
  fi
  log "placeholder: install NVIDIA driver stack (default target currently planned as nvidia-driver-595-open or policy-driven variant)"
}

detect_recommended_nvidia_package() {
  local devices_output pkg
  devices_output="$(ubuntu-drivers devices 2>/dev/null || true)"
  pkg="$(printf '%s\n' "$devices_output" | awk '/recommended/ {print $3; exit}')"
  if [[ -z "$pkg" ]]; then
    pkg="$(printf '%s\n' "$devices_output" | awk '/nvidia-driver-[0-9]+/ {print $3; exit}')"
  fi
  printf '%s\n' "$pkg"
}

install_nvidia_590_open_from_known_good_flow() {
  local pkg
  if ! is_apt_system; then
    die "NVIDIA install module currently supports apt-based Ubuntu/Debian systems only"
  fi
  log "installing NVIDIA using Ubuntu's recommended dynamic driver selection"
  sudo apt update
  sudo apt install -y software-properties-common ubuntu-drivers-common build-essential "linux-headers-$(uname -r)"
  if mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
    warn "Secure Boot appears to be enabled. NVIDIA kernel modules may fail to load until Secure Boot is disabled or the module is enrolled."
  fi
  sudo apt purge -y 'nvidia-*' || true
  sudo apt autoremove -y || true

  pkg="$(detect_recommended_nvidia_package)"
  if [[ -z "$pkg" ]]; then
    warn "Could not detect recommended NVIDIA package from Ubuntu repos; trying graphics-drivers PPA fallback"
    sudo add-apt-repository ppa:graphics-drivers/ppa -y
    sudo apt update
    pkg="$(detect_recommended_nvidia_package)"
  fi

  [[ -n "$pkg" ]] || die "Could not detect a recommended NVIDIA driver package."
  log "installing explicit NVIDIA package: $pkg"
  sudo apt install -y "$pkg"

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
