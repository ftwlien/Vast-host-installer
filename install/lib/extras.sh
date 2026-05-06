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

install_gpu_burn() {
  local target_user target_home repo_dir binary install_dir wrapper home_launcher bashrc marker
  target_user="$(installer_target_user)"
  target_home="$(installer_target_home "$target_user")"
  repo_dir="${target_home}/gpu-burn"
  binary="${repo_dir}/gpu_burn"
  install_dir="/opt/gpu-burn"
  wrapper="/usr/local/bin/gpu_burn"
  home_launcher="${target_home}/gpu_burn"
  bashrc="${target_home}/.bashrc"
  marker="# vast-host-installer gpu_burn shortcuts"

  banner "Optional Extra - gpu-burn Stress Test"

  if ! command -v nvidia-smi >/dev/null 2>&1; then
    die "gpu-burn was requested, but nvidia-smi is missing. Run NVIDIA setup first."
  fi
  if ! nvidia-smi >/dev/null 2>&1; then
    die "gpu-burn was requested, but NVIDIA is not ready (nvidia-smi failed)."
  fi

  step "Installing gpu-burn build dependencies"
  sudo apt-get update
  sudo apt-get install -y git build-essential nvidia-cuda-toolkit

  if [[ -d "$repo_dir/.git" ]]; then
    step "Updating existing gpu-burn repo"
    sudo -H -u "$target_user" git -C "$repo_dir" pull --ff-only
  else
    step "Cloning gpu-burn repo"
    sudo -H -u "$target_user" git clone https://github.com/wilicc/gpu-burn.git "$repo_dir"
  fi

  step "Building gpu-burn"
  sudo -H -u "$target_user" make -C "$repo_dir"
  [[ -x "$binary" ]] || die "gpu-burn build failed: ${binary} was not created"

  step "Installing gpu-burn runtime files"
  sudo rm -rf "$install_dir"
  sudo install -d -m 0755 "$install_dir"
  sudo cp -a "$repo_dir"/. "$install_dir"/
  sudo chmod -R a+rX "$install_dir"
  sudo chmod 0755 "$install_dir/gpu_burn"

  step "Installing gpu_burn command"
  sudo tee "$wrapper" >/dev/null <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$install_dir"
exec "$install_dir/gpu_burn" "\$@"
EOF
  sudo chmod 0755 "$wrapper"

  step "Installing ./gpu_burn launcher in ${target_home}"
  sudo tee "$home_launcher" >/dev/null <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$wrapper" "\$@"
EOF
  sudo chmod 0755 "$home_launcher"
  sudo chown "$target_user:$target_user" "$home_launcher"

  step "Installing gpu_burn shell shortcuts"
  if ! sudo -H -u "$target_user" grep -Fq "$marker" "$bashrc" 2>/dev/null; then
    sudo -H -u "$target_user" tee -a "$bashrc" >/dev/null <<EOF

$marker
gpu_burn() { /usr/local/bin/gpu_burn "\$@"; }
function ./gpu_burn() { /usr/local/bin/gpu_burn "\$@"; }
EOF
  fi

  [[ -x "$wrapper" ]] || die "gpu_burn wrapper was not created at ${wrapper}"
  [[ -x "$home_launcher" ]] || die "home gpu_burn launcher was not created at ${home_launcher}"

  success "gpu-burn installed. Test with: gpu_burn -tc -m 100% 60"
}

install_cpu_burn() {
  local wrapper
  wrapper="/usr/local/bin/cpu_burn"

  banner "Optional Extra - CPU Burn Stress Test"

  step "Installing CPU stress-test dependency"
  sudo apt-get update
  sudo apt-get install -y stress-ng

  step "Installing cpu_burn command"
  sudo tee "$wrapper" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

seconds="${1:-60}"
case "$seconds" in
  ''|*[!0-9]*)
    echo "Usage: cpu_burn [seconds]" >&2
    echo "Example: cpu_burn 60" >&2
    exit 2
    ;;
esac

exec stress-ng --cpu 0 --cpu-method matrixprod --verify --metrics-brief --timeout "${seconds}s"
EOF
  sudo chmod 0755 "$wrapper"
  sudo bash -n "$wrapper"

  if ! command -v stress-ng >/dev/null 2>&1; then
    die "stress-ng install failed: command not found after apt install"
  fi
  [[ -x "$wrapper" ]] || die "cpu_burn wrapper was not created at ${wrapper}"

  success "CPU burn installed. Test with: cpu_burn 60"
}

install_full_burn_if_ready() {
  local wrapper
  wrapper="/usr/local/bin/full_burn"

  if ! command -v cpu_burn >/dev/null 2>&1 || ! command -v gpu_burn >/dev/null 2>&1; then
    return 0
  fi

  step "Installing full_burn combined stress-test command"
  sudo tee "$wrapper" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

seconds="${1:-7200}"
case "$seconds" in
  ''|*[!0-9]*)
    echo "Usage: full_burn [seconds]" >&2
    echo "Example: full_burn 7200" >&2
    exit 2
    ;;
esac

echo "Starting CPU + GPU burn for ${seconds}s"
cpu_burn "$seconds" &
cpu_pid=$!
gpu_burn -tc -m 100% "$seconds" &
gpu_pid=$!

cleanup() {
  kill "$cpu_pid" "$gpu_pid" >/dev/null 2>&1 || true
  wait "$cpu_pid" >/dev/null 2>&1 || true
  wait "$gpu_pid" >/dev/null 2>&1 || true
}
trap 'cleanup; exit 130' INT TERM

cpu_status=0
gpu_status=0
wait "$cpu_pid" || cpu_status=$?
wait "$gpu_pid" || gpu_status=$?

if [[ "$cpu_status" -ne 0 || "$gpu_status" -ne 0 ]]; then
  echo "full_burn finished with errors: cpu=${cpu_status}, gpu=${gpu_status}" >&2
  exit 1
fi

echo "full_burn completed successfully"
EOF
  sudo chmod 0755 "$wrapper"
  sudo bash -n "$wrapper"
  success "Full burn installed. Test with: full_burn 7200"
}

install_gpu_fan_control() {
  banner "Optional Extra - Aggressive Vast.ai GPU Fan Control"

  if ! command -v nvidia-smi >/dev/null 2>&1; then
    die "GPU fan control was requested, but nvidia-smi is missing. Run NVIDIA setup first."
  fi
  if ! nvidia-smi >/dev/null 2>&1; then
    die "GPU fan control was requested, but NVIDIA is not ready (nvidia-smi failed)."
  fi

  step "Installing Xorg/nvidia-settings runtime dependencies"
  sudo apt-get update
  sudo apt-get install -y xserver-xorg-core nvidia-settings libxv1

  step "Ensuring NVIDIA Xorg config exposes all GPUs and fan controls"
  sudo nvidia-xconfig -a --cool-bits=28 --allow-empty-initial-configuration --enable-all-gpus || true

  step "Installing headless NVIDIA Xorg service"
  sudo tee /etc/systemd/system/nvidia-xorg.service >/dev/null <<'EOF'
[Unit]
Description=NVIDIA Headless Xorg
After=nvidia-persistenced.service
Wants=nvidia-persistenced.service

[Service]
Type=simple
ExecStartPre=/bin/sleep 15
ExecStart=/usr/bin/X :0 -noreset
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

  step "Installing aggressive Vast.ai fan curve"
  sudo tee /usr/local/bin/gpu-fan.sh >/dev/null <<'EOF'
#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=/root/.Xauthority

sleep 10

while true; do
    MAXTEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits | sort -nr | head -n1)

    GPUS=$(nvidia-settings --ctrl-display=:0 -q gpus 2>/dev/null | grep -o "gpu:[0-9]*" | sort -u)
    FANS=$(nvidia-settings --ctrl-display=:0 -q fans 2>/dev/null | grep -o "fan:[0-9]*" | sort -u)

    if [ "$MAXTEMP" -lt 50 ]; then
        MODE="auto"
        unset SPEED
    elif [ "$MAXTEMP" -lt 60 ]; then
        SPEED=50
        MODE="manual"
    elif [ "$MAXTEMP" -lt 70 ]; then
        SPEED=75
        MODE="manual"
    elif [ "$MAXTEMP" -lt 72 ]; then
        SPEED=90
        MODE="manual"
    else
        SPEED=100
        MODE="manual"
    fi

    echo "$(date) | Temp: $MAXTEMP°C -> Mode: $MODE ${SPEED:-} | GPUs: $GPUS | Fans: $FANS"

    for gpu in $GPUS; do
        if [ "$MODE" = "auto" ]; then
            nvidia-settings --ctrl-display=:0 -a "[$gpu]/GPUFanControlState=0" >/dev/null 2>&1
        else
            nvidia-settings --ctrl-display=:0 -a "[$gpu]/GPUFanControlState=1" >/dev/null 2>&1
        fi
    done

    if [ "$MODE" = "manual" ]; then
        for fan in $FANS; do
            nvidia-settings --ctrl-display=:0 -a "[$fan]/GPUTargetFanSpeed=$SPEED" >/dev/null 2>&1
        done
    fi

    sleep 5
done
EOF
  sudo chmod 0755 /usr/local/bin/gpu-fan.sh
  sudo bash -n /usr/local/bin/gpu-fan.sh

  step "Installing GPU fan control service"
  sudo tee /etc/systemd/system/gpu-fan.service >/dev/null <<'EOF'
[Unit]
Description=Smart NVIDIA GPU Fan Control
After=nvidia-xorg.service
Requires=nvidia-xorg.service

[Service]
Type=simple
ExecStartPre=/bin/sleep 10
ExecStart=/usr/local/bin/gpu-fan.sh
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

  sudo systemd-analyze verify /etc/systemd/system/nvidia-xorg.service /etc/systemd/system/gpu-fan.service >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl enable nvidia-xorg.service gpu-fan.service >/dev/null

  step "Starting headless Xorg and fan control"
  if ! systemctl is-active --quiet nvidia-xorg.service; then
    sudo systemctl start nvidia-xorg.service
  fi
  sudo systemctl restart gpu-fan.service

  sleep 15
  systemctl is-active --quiet nvidia-xorg.service || die "nvidia-xorg.service did not become active"
  systemctl is-active --quiet gpu-fan.service || die "gpu-fan.service did not become active"
  DISPLAY=:0 XAUTHORITY=/root/.Xauthority nvidia-settings -q gpus -q fans >/dev/null 2>&1 || die "nvidia-settings cannot see GPUs/fans on DISPLAY=:0"

  success "Aggressive Vast.ai GPU fan control installed and running"
}
