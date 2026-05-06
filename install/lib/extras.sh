#!/usr/bin/env bash
set -euo pipefail

installer_target_user() {
  if [[ -n "${TARGET_USER:-}" ]]; then
    printf '%s\n' "$TARGET_USER"
    return 0
  fi
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s\n' "$SUDO_USER"
    return 0
  fi
  awk -F: '$3 >= 1000 && $1 != "nobody" && $7 !~ /(nologin|false)$/ {print $1; exit}' /etc/passwd
}

installer_target_home() {
  local target_user="$1" target_home
  target_home="$(getent passwd "$target_user" | cut -d: -f6)"
  [[ -n "$target_home" ]] || die "Could not find home directory for target user: $target_user"
  printf '%s\n' "$target_home"
}

install_vast_cli() {
  local target_user target_home user_local_bin vastai_bin wrapper

  banner "Optional Extra - Vast CLI"
  target_user="$(installer_target_user)"
  target_home="$(installer_target_home "$target_user")"
  user_local_bin="${target_home}/.local/bin"
  vastai_bin="${user_local_bin}/vastai"
  wrapper="/usr/local/bin/vastai"

  if ! python3 -m pip --version >/dev/null 2>&1; then
    step "Installing python3-pip"
    sudo apt-get update
    sudo apt-get install -y python3-pip
  fi

  step "Installing Vast CLI"
  sudo -H -u "$target_user" python3 -m pip install --user --upgrade vastai

  sudo -H -u "$target_user" mkdir -p "$user_local_bin"
  if ! sudo -H -u "$target_user" grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "${target_home}/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' | sudo -H -u "$target_user" tee -a "${target_home}/.bashrc" >/dev/null
  fi
  export PATH="${user_local_bin}:${PATH}"
  hash -r || true

  [[ -x "$vastai_bin" ]] || die "Vast CLI install failed: ${vastai_bin} was not created by pip install"

  step "Verifying Vast CLI as ${target_user}"
  sudo -H -u "$target_user" "$vastai_bin" --help >/dev/null 2>&1 || die "Vast CLI install failed: ${vastai_bin} exists but does not run as ${target_user}"

  step "Creating /usr/local/bin/vastai wrapper"
  sudo tee "$wrapper" >/dev/null <<EOF
#!/bin/sh
if [ "\$(id -un)" = "$target_user" ]; then
  exec "$vastai_bin" "\$@"
fi
exec sudo -H -u "$target_user" "$vastai_bin" "\$@"
EOF
  sudo chmod 0755 "$wrapper"
  hash -r || true

  [[ -x "$wrapper" ]] || die "Vast CLI wrapper was not created at ${wrapper}"
  success "Vast CLI installed and ready"
}

install_rig_monitor_placeholder() {
  local target_user target_home repo_dir wrapper sudoers_file sudoers_tmp invoking_user
  target_user="$(installer_target_user)"
  target_home="$(installer_target_home "$target_user")"
  repo_dir="${target_home}/rig-monitor"
  wrapper="/usr/local/bin/rig-monitor"
  sudoers_file="/etc/sudoers.d/rig-monitor-launcher"
  banner "Optional Extra - rig-monitor"
  if [[ -d "$repo_dir/.git" ]]; then
    step "Updating existing rig-monitor repo"
    sudo -H -u "$target_user" git -C "$repo_dir" pull --ff-only
  else
    step "Cloning rig-monitor repo"
    sudo -H -u "$target_user" git clone https://github.com/ftwlien/rig-monitor.git "$repo_dir"
  fi
  step "Running rig-monitor installer"
  HOME="$target_home" bash "$repo_dir/scripts/install.sh"

  step "Creating rig-monitor launcher for ${target_user}"
  sudo tee "$wrapper" >/dev/null <<EOF
#!/usr/bin/env bash
set -euo pipefail

target_user="$target_user"
repo_dir="$repo_dir"

if [ "\$(id -un)" = "\$target_user" ]; then
  cd "\$repo_dir"
  exec python3 app.py "\$@"
fi

exec sudo -H -u "\$target_user" "$wrapper" "\$@"
EOF
  sudo chmod 0755 "$wrapper"

  step "Installing rig-monitor sudoers rules"
  invoking_user="${SUDO_USER:-}"
  sudoers_tmp="$(mktemp)"
  {
    echo "# Managed by vast-host-installer. Lets the bootstrap/operator shell run rig-monitor as ${target_user}."
    echo "${target_user} ALL=(root) NOPASSWD: /usr/local/bin/gputemps"
    if [[ -n "$invoking_user" && "$invoking_user" != "root" && "$invoking_user" != "$target_user" ]]; then
      echo "${invoking_user} ALL=(${target_user}) NOPASSWD: ${wrapper}"
      echo "${invoking_user} ALL=(${target_user}) NOPASSWD: ${wrapper} *"
    fi
    if id vastbootstrap >/dev/null 2>&1 && [[ "vastbootstrap" != "$target_user" && "vastbootstrap" != "$invoking_user" ]]; then
      echo "vastbootstrap ALL=(${target_user}) NOPASSWD: ${wrapper}"
      echo "vastbootstrap ALL=(${target_user}) NOPASSWD: ${wrapper} *"
    fi
  } > "$sudoers_tmp"
  if command -v visudo >/dev/null 2>&1; then
    sudo visudo -cf "$sudoers_tmp" >/dev/null
  fi
  sudo install -m 0440 "$sudoers_tmp" "$sudoers_file"
  rm -f "$sudoers_tmp"

  if command -v rig-monitor >/dev/null 2>&1 || [[ -x "$wrapper" ]]; then
    success "rig-monitor installed"
  else
    die "rig-monitor install was requested but the command is still missing"
  fi
}

install_fleet_health_placeholder() {
  local target_user target_home repo_dir
  target_user="$(installer_target_user)"
  target_home="$(installer_target_home "$target_user")"
  repo_dir="${target_home}/Fleet-Health-Check-public"
  banner "Optional Extra - Fleet Health Check"
  if [[ -d "$repo_dir/.git" ]]; then
    step "Updating existing Fleet Health Check repo"
    sudo -H -u "$target_user" git -C "$repo_dir" pull --ff-only
  else
    step "Cloning Fleet Health Check repo"
    sudo -H -u "$target_user" git clone https://github.com/ftwlien/Fleet-Health-Check-public.git "$repo_dir"
  fi
  step "Running Fleet Health Check prerequisite installer"
  HOME="$target_home" bash "$repo_dir/install-fleet-health-prereqs.sh"
  success "Fleet Health Check prerequisites installed"
}
