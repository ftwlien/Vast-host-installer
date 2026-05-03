#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../install/lib/common.sh
source "$ROOT_DIR/install/lib/common.sh"

if [[ "${1:-}" != "--yes" ]]; then
  banner "Reset Vast Host Installer State"
  warn "This removes installer-added userspace tools and helper repos so you can test again without reinstalling Ubuntu."
  warn "It does NOT try to uninstall NVIDIA drivers, Docker, or undo the full Vast host setup."
  echo
  echo "It will remove things like:"
  echo "- ~/rig-monitor"
  echo "- ~/Fleet-Health-Check-public"
  echo "- ~/.local/bin/rig-monitor"
  echo "- /usr/local/bin/rig-monitor"
  echo "- /usr/local/bin/gputemps"
  echo "- Vast CLI from user pip site-packages if present"
  echo "- installer resume state files"
  echo
  command_box "bash scripts/reset-host-installer-state.sh --yes"
  exit 0
fi

banner "Reset Vast Host Installer State"

remove_if_exists() {
  local target="$1"
  if [[ -e "$target" || -L "$target" ]]; then
    step "Removing $target"
    rm -rf "$target"
  fi
}

sudo_remove_if_exists() {
  local target="$1"
  if sudo test -e "$target" -o -L "$target"; then
    step "Removing $target"
    sudo rm -rf "$target"
  fi
}

step "Removing installer resume state"
remove_if_exists "$ROOT_DIR/install/.resume-state"
remove_if_exists "$ROOT_DIR/install/.first-boot-answers"
remove_if_exists "$ROOT_DIR/install/.planned-profile"

step "Removing rig-monitor repo and launchers"
remove_if_exists "$HOME/rig-monitor"
remove_if_exists "$HOME/.local/bin/rig-monitor"
sudo_remove_if_exists "/usr/local/bin/rig-monitor"
remove_if_exists "$HOME/.gputemps-wrapper.sh"
sudo_remove_if_exists "/usr/local/bin/gputemps"
sudo_remove_if_exists "/etc/sudoers.d/rig-monitor-gputemps"
remove_if_exists "$HOME/gddr6-core-junction-vram-temps"

step "Removing Fleet Health Check repo and helper sudoers"
remove_if_exists "$HOME/Fleet-Health-Check-public"
sudo_remove_if_exists "/etc/sudoers.d/smartctl-fleet-health-check"
sudo_remove_if_exists "/etc/sudoers.d/gputemps-fleet-health-check"

step "Removing Vast CLI from user install paths if present"
if command -v python3 >/dev/null 2>&1 && python3 -m pip --version >/dev/null 2>&1; then
  python3 -m pip uninstall -y vastai || true
else
  warn "python3 -m pip is unavailable; skipping pip uninstall for vastai"
fi
remove_if_exists "$HOME/.local/bin/vastai"

step "Removing common user-local Python package leftovers for Vast CLI"
remove_if_exists "$HOME/.local/lib/python3.10/site-packages/vastai"
remove_if_exists "$HOME/.local/lib/python3.10/site-packages/vastai-"*
remove_if_exists "$HOME/.local/bin/activate-global-python-argcomplete"
remove_if_exists "$HOME/.local/bin/python-argcomplete-check-easy-install-script"
remove_if_exists "$HOME/.local/bin/register-python-argcomplete"

success "Reset complete"
warn "This is a userspace/tooling cleanup only. NVIDIA, Docker, system packages, and live Vast host config may still remain."
