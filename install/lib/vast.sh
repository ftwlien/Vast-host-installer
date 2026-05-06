#!/usr/bin/env bash
set -euo pipefail

install_vast_host_from_known_good_flow() {
  local api_key port_range install_cmd sanitized_cmd
  api_key="${VAST_API_KEY:-}"
  port_range="${VAST_PORT_RANGE:-}"
  install_cmd="${VAST_INSTALL_COMMAND:-}"

  if ! is_apt_system; then
    die "Vast install module currently supports apt-based Ubuntu/Debian systems only"
  fi

  log "installing Vast host from known-good guide flow"
  sudo apt install -y python3 wget netcat-openbsd

  if [[ -n "$install_cmd" ]]; then
    local vast_tmp
    if [[ "$install_cmd" == *"--interactive"* && ! -t 0 ]]; then
      die "The saved Vast install command is interactive. Run phase 3 from a real SSH/console terminal with: sudo /opt/vast-host-installer/bin/vast-host-installer --resume"
    fi
    vast_tmp="$(mktemp -d /tmp/vast-install.XXXXXX)"
    sanitized_cmd="$(printf '%s' "$install_cmd" | sed -E 's/[[:space:]]*;?[[:space:]]*history -d .*?$//')"
    log "running provided Vast install command in $vast_tmp"
    set +e
    run_vast_command_direct bash -lc "cd '$vast_tmp' && $sanitized_cmd"
    vast_rc=$?
    set -e
    inspect_vast_install_result_or_die "$vast_rc"
  else
    [[ -n "$api_key" && "$api_key" != "***" ]] || die "Vast install command is missing. Re-run first setup and paste the full Vast.ai host install command."
    rm -f /tmp/vast-install.sh
    wget -q https://console.vast.ai/install -O /tmp/vast-install.sh
    set +e
    run_vast_command_direct sudo python3 /tmp/vast-install.sh "$api_key"
    vast_rc=$?
    set -e
    inspect_vast_install_result_or_die "$vast_rc"
  fi

  repair_vast_metrics_permissions

  if [[ -n "$port_range" ]]; then
    sudo mkdir -p /var/lib/vastai_kaalia
    echo "$port_range" | sudo tee /var/lib/vastai_kaalia/host_port_range >/dev/null
    log "Vast install step completed with host port range $port_range"
  else
    log "Vast install step completed"
  fi

  verify_vast_core_install_or_die
}

run_vast_command_direct() {
  local rc
  step "Starting Vast.ai host installer"
  echo "Vast's installer is interactive and may print its own formatting."
  echo "After it says Done, it may spend a few more minutes finalizing services."
  echo "If it does not return within 8 minutes, this wrapper will continue only if Vast is healthy."

  if command -v timeout >/dev/null 2>&1; then
    timeout --foreground --preserve-status 8m "$@"
    rc=$?
    if [[ "$rc" -eq 124 || "$rc" -eq 143 ]]; then
      if vast_core_looks_installed; then
        warn "Vast installer did not return promptly after startup, but Vast services look healthy. Continuing with post-install extras."
        return 0
      fi
    fi
    return "$rc"
  fi

  "$@"
  rc=$?
  return "$rc"
}

repair_vast_metrics_permissions() {
  local metrics_script="/var/lib/vastai_kaalia/latest/launch_metrics_pusher.sh"
  if [[ -f "$metrics_script" ]]; then
    log "repairing Vast metrics launcher permissions"
    sudo chmod 755 "$metrics_script" || warn "Could not chmod Vast metrics launcher: $metrics_script"
    if systemctl cat vast_metrics >/dev/null 2>&1; then
      sudo systemctl daemon-reload || true
      sudo systemctl restart vast_metrics || warn "vast_metrics restart failed; check: systemctl status vast_metrics --no-pager"
    fi
  fi
}

inspect_vast_install_result_or_die() {
  local rc
  rc="$1"

  if [[ "$rc" -ne 0 ]]; then
    die "Vast install command exited with status ${rc}. If the output above mentioned 401 Unauthorized, generate a fresh Vast host install command and run Phase 3 again."
  fi
}

vast_core_looks_installed() {
  command -v docker >/dev/null 2>&1 || return 1
  systemctl is-active docker >/dev/null 2>&1 || return 1
  systemctl cat vastai >/dev/null 2>&1 || return 1
  systemctl is-active vastai >/dev/null 2>&1 || return 1
  return 0
}

verify_vast_core_install_or_die() {
  local waited=0
  command -v docker >/dev/null 2>&1 || die "Vast core install check failed: docker command is missing"
  systemctl is-active docker >/dev/null 2>&1 || die "Vast core install check failed: docker.service is not active"
  docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q 'nvidia' || die "Vast core install check failed: Docker NVIDIA runtime is missing"

  while [[ "$waited" -lt 60 ]]; do
    if systemctl cat vastai >/dev/null 2>&1 && systemctl is-active vastai >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done

  if ! systemctl cat vastai >/dev/null 2>&1; then
    die "Vast core install check failed: vastai.service was not created by the Vast install command"
  fi
  die "Vast core install check failed: vastai.service exists but is not active"
}

print_vast_post_install_notes() {
  cat <<'EOF'
NEXT_MANUAL_CHECKS:
- systemctl status vastai --no-pager
- cat /var/lib/vastai_kaalia/host_port_range
- curl -I https://console.vast.ai
- nvidia-smi
- verify firewall/router rules for Vast port exposure
EOF
}
