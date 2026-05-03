#!/usr/bin/env bash
set -euo pipefail

install_vast_cli() {
  banner "Optional Extra - Vast CLI"
  python3 -m pip install --user vastai
  if ! grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "${HOME}/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "${HOME}/.bashrc"
  fi
  export PATH="${HOME}/.local/bin:${PATH}"
  command -v vastai >/dev/null 2>&1 || die "Vast CLI install completed but 'vastai' is still not on PATH"
  success "Vast CLI installed"
}

install_rig_monitor_placeholder() {
  local repo_dir
  repo_dir="${HOME}/rig-monitor"
  banner "Optional Extra - rig-monitor"
  if [[ -d "$repo_dir/.git" ]]; then
    step "Updating existing rig-monitor repo"
    git -C "$repo_dir" pull --ff-only
  else
    step "Cloning rig-monitor repo"
    git clone https://github.com/ftwlien/rig-monitor.git "$repo_dir"
  fi
  step "Running rig-monitor installer"
  bash "$repo_dir/scripts/install.sh"
  if command -v rig-monitor >/dev/null 2>&1 || [[ -x /usr/local/bin/rig-monitor ]]; then
    success "rig-monitor installed"
  else
    die "rig-monitor install was requested but the command is still missing"
  fi
}

install_fleet_health_placeholder() {
  local repo_dir
  repo_dir="${HOME}/Fleet-Health-Check-public"
  banner "Optional Extra - Fleet Health Check"
  if [[ -d "$repo_dir/.git" ]]; then
    step "Updating existing Fleet Health Check repo"
    git -C "$repo_dir" pull --ff-only
  else
    step "Cloning Fleet Health Check repo"
    git clone https://github.com/ftwlien/Fleet-Health-Check-public.git "$repo_dir"
  fi
  step "Running Fleet Health Check prerequisite installer"
  bash "$repo_dir/install-fleet-health-prereqs.sh"
  success "Fleet Health Check prerequisites installed"
}
