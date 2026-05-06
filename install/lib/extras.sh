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
  local cpu_wrapper ram_wrapper
  cpu_wrapper="/usr/local/bin/cpu_burn"
  ram_wrapper="/usr/local/bin/memtester"

  banner "Optional Extra - CPU/RAM Burn Stress Tests"

  step "Installing CPU/RAM stress-test dependencies"
  sudo apt-get update
  sudo apt-get install -y stress-ng memtester memtest86+

  step "Installing cpu_burn command"
  sudo tee "$cpu_wrapper" >/dev/null <<'EOF'
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
  sudo chmod 0755 "$cpu_wrapper"
  sudo bash -n "$cpu_wrapper"

  step "Installing memtester command"
  sudo tee "$ram_wrapper" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

seconds="${1:-60}"
case "$seconds" in
  ''|*[!0-9]*)
    echo "Usage: memtester [seconds]" >&2
    echo "Example: memtester 60" >&2
    exit 2
    ;;
esac

memory_mb="${MEMTESTER_MB:-}"
if [[ -z "$memory_mb" ]]; then
  available_mb="$(awk '/MemAvailable:/ {printf "%d", $2 / 1024}' /proc/meminfo)"
  memory_mb=$(( available_mb * 80 / 100 ))
fi
if (( memory_mb < 64 )); then
  echo "Not enough available memory for memtester (${memory_mb}M calculated)" >&2
  exit 1
fi

# Use timeout for seconds-based UX while preserving memtester's dedicated RAM test behavior.
exec timeout --foreground "${seconds}s" /usr/bin/memtester "${memory_mb}M" 1
EOF
  sudo chmod 0755 "$ram_wrapper"
  sudo bash -n "$ram_wrapper"

  if ! command -v stress-ng >/dev/null 2>&1; then
    die "stress-ng install failed: command not found after apt install"
  fi
  [[ -x "$cpu_wrapper" ]] || die "cpu_burn wrapper was not created at ${cpu_wrapper}"
  [[ -x "$ram_wrapper" ]] || die "memtester wrapper was not created at ${ram_wrapper}"

  success "CPU/RAM burn installed. Test with: cpu_burn 60 and memtester 60. Memtest86+ is available from the boot menu."
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

log_dir="${FULL_BURN_LOG_DIR:-$HOME/burn-logs}"
mkdir -p "$log_dir"
log_file="$log_dir/full_burn-$(date +%Y%m%d-%H%M%S).log"

exec > >(tee -a "$log_file") 2>&1

echo "full_burn log: $log_file"
echo "Starting CPU + GPU + RAM burn for ${seconds}s"
echo "Host: $(hostname)"
echo "Start: $(date -Is)"

cpu_burn "$seconds" &
cpu_pid=$!
gpu_burn -tc -m 100% "$seconds" &
gpu_pid=$!
ram_pressure_pid=""
if command -v stress-ng >/dev/null 2>&1; then
  stress-ng --vm 0 --vm-bytes 50% --verify --metrics-brief --timeout "${seconds}s" &
  ram_pressure_pid=$!
else
  echo "stress-ng not found; running CPU + GPU only" >&2
fi

cleanup() {
  kill "$cpu_pid" "$gpu_pid" ${ram_pressure_pid:+"$ram_pressure_pid"} >/dev/null 2>&1 || true
  wait "$cpu_pid" >/dev/null 2>&1 || true
  wait "$gpu_pid" >/dev/null 2>&1 || true
  if [[ -n "$ram_pressure_pid" ]]; then
    wait "$ram_pressure_pid" >/dev/null 2>&1 || true
  fi
}
trap 'cleanup; exit 130' INT TERM

cpu_status=0
gpu_status=0
ram_status=0
wait "$cpu_pid" || cpu_status=$?
wait "$gpu_pid" || gpu_status=$?
if [[ -n "$ram_pressure_pid" ]]; then
  wait "$ram_pressure_pid" || ram_status=$?
fi

if [[ "$cpu_status" -ne 0 || "$gpu_status" -ne 0 || "$ram_status" -ne 0 ]]; then
  echo "full_burn finished with errors: cpu=${cpu_status}, gpu=${gpu_status}, ram=${ram_status}" >&2
  exit 1
fi

echo "End: $(date -Is)"
echo "full_burn completed successfully"
echo "Log saved to: $log_file"
EOF
  sudo chmod 0755 "$wrapper"
  sudo bash -n "$wrapper"
  success "Full burn installed. Test with: full_burn 7200"
}

install_host_polish_tools() {
  local storage_layout disk_health vast_ready_check vast_cleanup
  storage_layout="/usr/local/bin/storage_layout"
  disk_health="/usr/local/bin/disk_health"
  vast_ready_check="/usr/local/bin/vast_ready_check"
  vast_cleanup="/usr/local/bin/vast_cleanup"

  banner "Host Polish Tools"

  step "Installing disk/network diagnostic dependencies"
  sudo apt-get update
  sudo apt-get install -y smartmontools nvme-cli pciutils curl ca-certificates lsb-release mokutil

  if ! command -v speedtest >/dev/null 2>&1 && ! command -v speedtest-cli >/dev/null 2>&1; then
    step "Installing speedtest-cli fallback"
    sudo apt-get install -y speedtest-cli || true
  fi

  step "Installing storage_layout command"
  sudo tee "$storage_layout" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

echo "== Storage layout overview =="
echo "Host: $(hostname)"
echo "Time: $(date -Is)"
echo

printf '%-12s %-10s %-8s %-8s %-12s %-20s %s\n' "DEVICE" "SIZE" "TYPE" "FSTYPE" "MOUNT" "MODEL" "UUID"
lsblk -e7 -P -o NAME,PATH,SIZE,TYPE,FSTYPE,UUID,MOUNTPOINTS,MODEL | while IFS= read -r line; do
  eval "$line"
  mount="${MOUNTPOINTS:-}"
  mount="${mount//$'\n'/,}"
  printf '%-12s %-10s %-8s %-8s %-12s %-20s %s\n' "${PATH:-/dev/$NAME}" "${SIZE:-}" "${TYPE:-}" "${FSTYPE:--}" "${mount:--}" "${MODEL:--}" "${UUID:--}"
done

echo
echo "== Filesystem usage =="
df -hT / /boot/efi /var/lib/docker 2>/dev/null || df -hT

echo
echo "== Important mounts =="
for mount in / /boot/efi /var/lib/docker; do
  if findmnt "$mount" >/dev/null 2>&1; then
    source="$(findmnt -no SOURCE "$mount")"
    fstype="$(findmnt -no FSTYPE "$mount")"
    opts="$(findmnt -no OPTIONS "$mount")"
    echo "$mount -> $source ($fstype)"
    if [[ "$mount" == "/var/lib/docker" ]]; then
      if [[ "$fstype" == "xfs" && "$opts" == *prjquota* ]]; then
        echo "  Docker storage: OK, XFS with prjquota"
      else
        echo "  Docker storage: WARNING, expected XFS with prjquota"
        echo "  Options: $opts"
      fi
    fi
  else
    echo "$mount -> not mounted"
  fi
done
SCRIPT
  sudo chmod 0755 "$storage_layout"
  sudo bash -n "$storage_layout"

  step "Installing disk_health command"
  sudo tee "$disk_health" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

echo "== Disk layout =="
lsblk -e7 -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS,MODEL,SERIAL

echo
echo "== Filesystem usage =="
df -hT / /boot/efi /var/lib/docker 2>/dev/null || df -hT

echo
echo "== NVMe SMART summaries =="
shopt -s nullglob
nvmes=(/dev/nvme*n1)
if ((${#nvmes[@]} == 0)); then
  echo "No NVMe disks found."
else
  for dev in "${nvmes[@]}"; do
    echo
    echo "--- $dev ---"
    if command -v nvme >/dev/null 2>&1; then
      sudo nvme smart-log "$dev" 2>/dev/null || true
    fi
    if command -v smartctl >/dev/null 2>&1; then
      sudo smartctl -H -A "$dev" 2>/dev/null || true
    fi
  done
fi
SCRIPT
  sudo chmod 0755 "$disk_health"
  sudo bash -n "$disk_health"

  step "Installing vast_ready_check command"
  sudo tee "$vast_ready_check" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -uo pipefail

pass=0
fail=0
warn=0

ok() { printf '✓ %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '✗ %s\n' "$*"; fail=$((fail+1)); }
soft() { printf '! %s\n' "$*"; warn=$((warn+1)); }
has() { command -v "$1" >/dev/null 2>&1; }
active() { systemctl is-active --quiet "$1" 2>/dev/null; }
enabled() { systemctl is-enabled --quiet "$1" 2>/dev/null; }

check_service() {
  local svc="$1"
  if systemctl list-unit-files "${svc}.service" --no-legend 2>/dev/null | grep -q "^${svc}\.service"; then
    active "$svc" && ok "${svc} service active" || bad "${svc} service not active"
  else
    soft "${svc} service not installed"
  fi
}

echo "== Vast host readiness check =="
echo "Host: $(hostname)"
echo "Time: $(date -Is)"
echo

has docker && ok "docker command installed" || bad "docker command missing"
check_service docker
check_service containerd
check_service vastai
if systemctl list-unit-files vast_metrics.service --no-legend 2>/dev/null | grep -q '^vast_metrics\.service'; then
  if active vast_metrics; then
    ok "vast_metrics service active"
  else
    launcher="/var/lib/vastai_kaalia/latest/launch_metrics_pusher.sh"
    if [[ -e "$launcher" && ! -x "$launcher" && "${EUID:-$(id -u)}" -eq 0 ]]; then
      soft "vast_metrics inactive; repairing launcher execute permission"
      chmod 0755 "$launcher" 2>/dev/null || true
      systemctl restart vast_metrics.service 2>/dev/null || true
      sleep 1
      active vast_metrics && ok "vast_metrics service active after permission repair" || bad "vast_metrics service not active; try: sudo chmod 0755 $launcher && sudo systemctl restart vast_metrics"
    else
      bad "vast_metrics service not active; try: sudo chmod 0755 /var/lib/vastai_kaalia/latest/launch_metrics_pusher.sh && sudo systemctl restart vast_metrics"
    fi
  fi
else
  soft "vast_metrics service not installed"
fi
check_service nvidia-persistenced
check_service nvidia-xorg
check_service gpu-fan

echo
if has nvidia-smi && nvidia-smi >/dev/null 2>&1; then
  ok "nvidia-smi works"
  nvidia-smi --query-gpu=index,name,driver_version,temperature.gpu,fan.speed,power.draw,memory.total,memory.used --format=csv,noheader,nounits 2>/dev/null | while IFS= read -r line; do
    echo "  GPU: $line"
  done
else
  bad "nvidia-smi failed"
fi

if has docker; then
  docker_root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
  [[ "$docker_root" == "/var/lib/docker" ]] && ok "Docker root is /var/lib/docker" || soft "Docker root is ${docker_root:-unknown}"
  runtimes="$(docker info --format '{{.Runtimes}}' 2>/dev/null || true)"
  [[ "$runtimes" == *nvidia* ]] && ok "Docker NVIDIA runtime present" || bad "Docker NVIDIA runtime missing"
fi

if findmnt /var/lib/docker >/dev/null 2>&1; then
  fs="$(findmnt -no FSTYPE /var/lib/docker 2>/dev/null || true)"
  opts="$(findmnt -no OPTIONS /var/lib/docker 2>/dev/null || true)"
  [[ "$fs" == "xfs" ]] && ok "/var/lib/docker is XFS" || soft "/var/lib/docker filesystem is ${fs:-unknown}"
  [[ "$opts" == *prjquota* ]] && ok "/var/lib/docker has prjquota" || bad "/var/lib/docker missing prjquota"
else
  bad "/var/lib/docker is not a separate mount"
fi

echo
if has mokutil; then
  sb="$(mokutil --sb-state 2>/dev/null || true)"
  [[ "$sb" == *disabled* || "$sb" == *not*enabled* ]] && ok "Secure Boot disabled" || soft "Secure Boot state: ${sb:-unknown}"
else
  soft "mokutil missing; Secure Boot state not checked"
fi

if has lspci; then
  echo
  echo "== GPU PCIe links =="
  while IFS= read -r bus; do
    [[ -n "$bus" ]] || continue
    echo "--- $bus ---"
    lspci -s "$bus" -vv 2>/dev/null | grep -E 'LnkCap:|LnkSta:' || true
  done < <(lspci -D | awk '/VGA compatible controller|3D controller|Display controller/ && /NVIDIA/ {print $1}')
fi

echo
if has speedtest; then
  echo "== Network speedtest =="
  timeout 90s speedtest 2>/dev/null || soft "speedtest failed or was cancelled"
elif has speedtest-cli; then
  echo "== Network speedtest =="
  timeout 90s speedtest-cli --simple 2>/dev/null || soft "speedtest-cli failed or was cancelled"
else
  soft "No speedtest command installed"
fi

echo
echo "Summary: ${pass} passed, ${warn} warnings, ${fail} failed"
(( fail == 0 ))
SCRIPT
  sudo chmod 0755 "$vast_ready_check"
  sudo bash -n "$vast_ready_check"

  step "Installing vast_cleanup command"
  sudo tee "$vast_cleanup" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo "$0" "$@"
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker command not found" >&2
  exit 1
fi

echo "Docker usage before cleanup:"
docker system df || true

echo
echo "WARNING: vast_cleanup should only run when the machine is idle/unlisted"
echo "and you are sure no customer data must be preserved."
echo
echo "This removes stopped containers, unused networks, dangling/unused images, and build cache."
echo "It intentionally does NOT use --volumes."
read -r -p "Type CLEAN IDLE MACHINE to continue: " answer
case "$answer" in
  "CLEAN IDLE MACHINE")
    docker system prune -af
    ;;
  *)
    echo "Cancelled."
    exit 0
    ;;
esac

echo
echo "Docker usage after cleanup:"
docker system df || true
SCRIPT
  sudo chmod 0755 "$vast_cleanup"
  sudo bash -n "$vast_cleanup"

  success "Host polish tools installed: storage_layout, disk_health, vast_ready_check, vast_cleanup"
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
