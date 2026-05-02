#!/usr/bin/env bash
set -euo pipefail

configure_docker_repo() {
  sudo install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  fi
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  fi
}

install_docker_from_known_good_flow() {
  if ! is_apt_system; then
    die "Docker install module currently supports apt-based Ubuntu/Debian systems only"
  fi
  local target_user
  target_user="${SUDO_USER:-$USER}"
  log "installing Docker using known-good onboarding flow"
  configure_docker_repo
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable docker
  sudo systemctl start docker
  sudo usermod -aG docker "$target_user" || true
}
