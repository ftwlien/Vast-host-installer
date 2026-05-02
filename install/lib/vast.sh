#!/usr/bin/env bash
set -euo pipefail

install_vast_host_from_known_good_flow() {
  local api_key port_range
  api_key="${VAST_API_KEY:-}"
  port_range="${VAST_PORT_RANGE:-40000-40019}"
  [[ -n "$api_key" ]] || die "VAST API key is required. Pass --vast-api-key <key> or set VAST_API_KEY."

  if ! is_apt_system; then
    die "Vast install module currently supports apt-based Ubuntu/Debian systems only"
  fi

  log "installing Vast host from known-good guide flow"
  sudo apt install -y python3 wget netcat-openbsd
  rm -f /tmp/vast-install.sh
  wget -q https://console.vast.ai/install -O /tmp/vast-install.sh
  sudo python3 /tmp/vast-install.sh "$api_key"

  sudo mkdir -p /var/lib/vastai_kaalia
  echo "$port_range" | sudo tee /var/lib/vastai_kaalia/host_port_range >/dev/null

  log "Vast install step completed with host port range $port_range"
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
