#!/usr/bin/env bash
set -euo pipefail

ensure_operator_user() {
  local username password
  username="$1"
  password="$2"

  [[ -n "$username" ]] || return 0
  if id "$username" >/dev/null 2>&1; then
    log "operator user already exists: $username"
  else
    log "creating operator user: $username"
    sudo useradd -m -s /bin/bash "$username"
  fi

  if [[ -n "$password" ]]; then
    echo "$username:$password" | sudo chpasswd
  fi

  sudo usermod -aG sudo "$username" || true
}

lock_bootstrap_user_after_handoff() {
  local final_user="${1:-}"
  local bootstrap_user="vastbootstrap"

  [[ -n "$final_user" ]] || return 0
  [[ "$final_user" != "$bootstrap_user" ]] || return 0
  id "$bootstrap_user" >/dev/null 2>&1 || return 0

  log "locking temporary bootstrap user after operator handoff: $bootstrap_user"
  sudo passwd -l "$bootstrap_user" >/dev/null 2>&1 || true
  sudo usermod -s /usr/sbin/nologin "$bootstrap_user" >/dev/null 2>&1 || true
}

set_final_hostname() {
  local hostname="$1"
  [[ -n "$hostname" ]] || return 0
  log "setting hostname to $hostname"
  sudo hostnamectl set-hostname "$hostname"
}
