#!/usr/bin/env bash
set -euo pipefail

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
  log "placeholder: fleet-health prereq install hook"
}
