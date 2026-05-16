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


has_blackwell_gpu() {
  nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null \
    | grep -Eiq '(^|[[:space:]])(RTX[[:space:]]+50|RTX[[:space:]]+5090|RTX[[:space:]]+5080|RTX[[:space:]]+5070|B200|GB200|Blackwell|GB20)'
}

install_cuda_13_2_toolkit_for_blackwell() {
  banner "CUDA Toolkit 13.2 for Blackwell/RTX 50 Burn Tools"
  step "Installing CUDA repo prerequisites"
  sudo apt-get update
  sudo apt-get install -y curl ca-certificates gnupg lsb-release

  step "Removing old CUDA 11/12 toolkit packages without touching NVIDIA drivers"
  local -a old_cuda_pkgs
  mapfile -t old_cuda_pkgs < <(
    dpkg-query -W -f='${binary:Package}\n' 2>/dev/null \
      | grep -E '^(nvidia-cuda-toolkit|nvidia-cuda-dev|nvidia-cuda-gdb|nvidia-cuda-doc|nvidia-cuda-toolkit-doc|libcudart11\.0|cuda-(toolkit|compiler|command-line-tools)-1[12]-)' \
      || true
  )
  if ((${#old_cuda_pkgs[@]})); then
    sudo apt-get purge -y "${old_cuda_pkgs[@]}"
  fi
  sudo apt-get autoremove -y || true

  local os_id os_version ubuntu_repo arch keyring_url keyring_deb
  os_id="ubuntu"
  os_version="22.04"
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_id="${ID:-ubuntu}"
    os_version="${VERSION_ID:-22.04}"
  fi
  ubuntu_repo="ubuntu${os_version//./}"
  case "$ubuntu_repo" in
    ubuntu2204|ubuntu2404) ;;
    *)
      log "Unsupported CUDA repo target ${os_id}/${os_version}; falling back to ubuntu2204 CUDA repo"
      ubuntu_repo="ubuntu2204"
      ;;
  esac

  arch="$(dpkg --print-architecture)"
  case "$arch" in
    amd64) arch="x86_64" ;;
    arm64) arch="sbsa" ;;
    *) die "Unsupported architecture for NVIDIA CUDA repo: ${arch}" ;;
  esac

  keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/${ubuntu_repo}/${arch}/cuda-keyring_1.1-1_all.deb"
  keyring_deb="/tmp/cuda-keyring_1.1-1_all.deb"
  step "Installing NVIDIA CUDA apt keyring for ${ubuntu_repo}/${arch}"
  curl -fsSL "$keyring_url" -o "$keyring_deb"
  sudo dpkg -i "$keyring_deb"
  rm -f "$keyring_deb"

  step "Installing cuda-toolkit-13-2"
  sudo apt-get update
  sudo apt-get install -y cuda-toolkit-13-2
  [[ -x /usr/local/cuda-13.2/bin/nvcc ]] || die "CUDA 13.2 install failed: /usr/local/cuda-13.2/bin/nvcc not found"
  sudo ln -sfn /usr/local/cuda-13.2 /usr/local/cuda
  /usr/local/cuda-13.2/bin/nvcc --version
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
  sudo apt-get install -y git build-essential

  if [[ -d "$repo_dir/.git" ]]; then
    step "Updating existing gpu-burn repo"
    sudo -H -u "$target_user" git -C "$repo_dir" pull --ff-only
  else
    step "Cloning gpu-burn repo"
    sudo -H -u "$target_user" git clone https://github.com/wilicc/gpu-burn.git "$repo_dir"
  fi

  local -a cuda_make_args
  cuda_make_args=()
  if has_blackwell_gpu; then
    install_cuda_13_2_toolkit_for_blackwell
    cuda_make_args=(COMPUTE=120 CUDAPATH=/usr/local/cuda-13.2 CUDA_VERSION=13.2.0)
  else
    step "Installing legacy gpu-burn CUDA build dependency"
    sudo apt-get install -y nvidia-cuda-toolkit
  fi

  step "Building gpu-burn"
  sudo -H -u "$target_user" make -C "$repo_dir" "${cuda_make_args[@]}"
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
args=("\$@")
last="\${args[-1]:-}"
if [[ "\$last" =~ ^[0-9]+$ ]] && command -v timeout >/dev/null 2>&1; then
  grace="\${GPU_BURN_TIMEOUT_GRACE:-30}"
  case "\$grace" in ''|*[!0-9]*) grace=30 ;; esac
  set +e
  timeout --kill-after=10s "\$((last + grace))s" "$install_dir/gpu_burn" "\$@"
  status="\$?"
  set -e
  if [[ "\$status" -eq 124 ]]; then
    echo "gpu_burn duration \${last}s reached; stopped after \${grace}s grace"
    exit 0
  fi
  exit "\$status"
fi
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
  ram_wrapper="/usr/local/bin/ram_burn"

  banner "Optional Extra - CPU/RAM Burn Stress Tests"

  step "Installing CPU/RAM stress-test dependencies"
  sudo apt-get update
  sudo apt-get install -y stress-ng stressapptest memtest86+

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

  step "Installing ram_burn command"
  sudo tee "$ram_wrapper" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
seconds="${1:-60}"
case "$seconds" in
  ''|*[!0-9]*) echo "Usage: ram_burn [seconds]" >&2; echo "Example: ram_burn 7200" >&2; exit 2 ;;
esac
if ! command -v stressapptest >/dev/null 2>&1; then
  echo "stressapptest command not found. Install package: sudo apt-get install -y stressapptest" >&2
  exit 1
fi
if [[ "${EUID:-$(id -u)}" -ne 0 && "${RAM_BURN_ALLOW_USER:-0}" != "1" ]]; then
  echo "Re-running with sudo..."
  exec sudo "$0" "$@"
fi
total_mb="$(awk '/MemTotal:/ {printf "%d", $2 / 1024}' /proc/meminfo)"
available_mb="$(awk '/MemAvailable:/ {printf "%d", $2 / 1024}' /proc/meminfo)"
reserve_mb="${RAM_BURN_RESERVE_MB:-8192}"
percent="${RAM_BURN_PERCENT:-90}"
case "$reserve_mb" in ''|*[!0-9]*) echo "RAM_BURN_RESERVE_MB must be a number" >&2; exit 2;; esac
case "$percent" in ''|*[!0-9]*) echo "RAM_BURN_PERCENT must be a number" >&2; exit 2;; esac
if [[ -n "${RAM_BURN_MB:-}" ]]; then
  memory_mb="$RAM_BURN_MB"
elif [[ -n "${STRESSAPPTEST_MB:-}" ]]; then
  memory_mb="$STRESSAPPTEST_MB"
else
  percent_target=$(( total_mb * percent / 100 ))
  available_target=$(( available_mb - reserve_mb ))
  if (( percent_target < available_target )); then memory_mb=$percent_target; else memory_mb=$available_target; fi
fi
max_mb=$(( available_mb - 2048 ))
if (( memory_mb > max_mb )); then memory_mb=$max_mb; fi
if (( memory_mb < 1024 )); then
  echo "Not enough available memory for ram_burn (${memory_mb}M calculated; total=${total_mb}M available=${available_mb}M reserve=${reserve_mb}M)" >&2
  exit 1
fi
memory_gib="$(awk -v mb="$memory_mb" 'BEGIN {printf "%.1f", mb/1024}')"
log_dir="${RAM_BURN_LOG_DIR:-${SUDO_USER:+/home/$SUDO_USER}/burn-logs}"
if [[ -z "$log_dir" || "$log_dir" == "/burn-logs" ]]; then log_dir="${HOME}/burn-logs"; fi
mkdir -p "$log_dir"
if [[ -n "${SUDO_USER:-}" && -d "/home/$SUDO_USER" ]]; then chown "$SUDO_USER:$SUDO_USER" "$log_dir" 2>/dev/null || true; fi
log_file="$log_dir/ram_burn-$(date +%Y%m%d-%H%M%S).log"
echo "ram_burn log: $log_file"
echo "Starting stressapptest RAM burn for ${seconds}s using ${memory_mb}M (${memory_gib}GiB)"
echo "Auto sizing: total=${total_mb}M available=${available_mb}M reserve=${reserve_mb}M percent=${percent}%"
echo "Command: stressapptest -W -s ${seconds} -M ${memory_mb} --pause_delay 999999"
stressapptest -W -s "$seconds" -M "$memory_mb" --pause_delay 999999 >"$log_file" 2>&1 &
sap_pid=$!
cleanup() { kill "$sap_pid" >/dev/null 2>&1 || true; wait "$sap_pid" >/dev/null 2>&1 || true; }
trap 'cleanup; exit 130' INT TERM
last_report=-10
status=0
while kill -0 "$sap_pid" >/dev/null 2>&1; do
  elapsed="$(ps -o etimes= -p "$sap_pid" 2>/dev/null | tr -d ' ' || echo 0)"; elapsed="${elapsed:-0}"
  if (( elapsed - last_report >= 10 )); then
    rss_kb="$(awk '/VmRSS:/ {print $2}' "/proc/${sap_pid}/status" 2>/dev/null || echo 0)"
    rss_gib="$(awk -v kb="${rss_kb:-0}" 'BEGIN {printf "%.1f", kb/1024/1024}')"
    echo "RAM used by stressapptest: ${rss_gib}GiB / ${memory_gib}GiB target (${elapsed}s elapsed)"
    last_report=$elapsed
  fi
  sleep 2
done
wait "$sap_pid" || status=$?
trap - INT TERM
if [[ "$status" -eq 0 ]]; then
  echo "ram_burn completed successfully"
  echo "Log saved to: $log_file"
  exit 0
fi
echo "ram_burn failed with exit code ${status}" >&2
echo "Last log lines:" >&2
tail -n 60 "$log_file" >&2 || true
exit "$status"
EOF
  sudo chmod 0755 "$ram_wrapper"
  sudo bash -n "$ram_wrapper"
  sudo tee /usr/local/bin/memtester >/dev/null <<'EOF'
#!/usr/bin/env bash
exec /usr/local/bin/ram_burn "$@"
EOF
  sudo chmod 0755 /usr/local/bin/memtester
  sudo bash -n /usr/local/bin/memtester

  if ! command -v stress-ng >/dev/null 2>&1; then
    die "stress-ng install failed: command not found after apt install"
  fi
  if ! command -v stressapptest >/dev/null 2>&1; then
    die "stressapptest install failed: command not found after apt install"
  fi
  [[ -x "$cpu_wrapper" ]] || die "cpu_burn wrapper was not created at ${cpu_wrapper}"
  [[ -x "$ram_wrapper" ]] || die "ram_burn wrapper was not created at ${ram_wrapper}"

  success "CPU/RAM burn installed. Test with: cpu_burn 60 and sudo ram_burn 60. Memtest86+ is available from the boot menu."
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
if command -v ram_burn >/dev/null 2>&1; then
  sudo RAM_BURN_PERCENT="${FULL_BURN_RAM_PERCENT:-90}" RAM_BURN_RESERVE_MB="${FULL_BURN_RAM_RESERVE_MB:-8192}" ram_burn "$seconds" &
  ram_pressure_pid=$!
else
  echo "ram_burn not found; running CPU + GPU only" >&2
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

install_vast_machine_id_tool() {
  local vast_machine_id="/usr/local/bin/vast_machine_id"
  step "Installing Vast machine ID helper"
  sudo tee "$vast_machine_id" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
machine_id_file="/var/lib/vastai_kaalia/machine_id"

usage() {
  cat <<'EOF'
Usage:
  sudo vast_machine_id show
  sudo vast_machine_id restore <machine_id>

Use show before reinstalling/wiping a Vast host so you can save the current
identity. Use restore during fresh setup before Vast.ai installs/registers.
EOF
}

cmd="${1:-show}"
case "$cmd" in
  show)
    if [[ -f "$machine_id_file" ]]; then
      echo "Vast machine ID: $(cat "$machine_id_file")"
      echo
      echo "Save this value somewhere safe before reinstalling if you want to preserve this host identity."
    else
      echo "No Vast machine ID found at $machine_id_file"
      exit 1
    fi
    ;;
  restore)
    id="${2:-}"
    if [[ -z "$id" ]]; then usage >&2; exit 2; fi
    if [[ ! "$id" =~ ^[A-Za-z0-9._:-]+$ ]]; then
      echo "Machine ID contains unexpected characters. Refusing." >&2
      exit 2
    fi
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then exec sudo "$0" "$@"; fi
    install -d -m 0755 /var/lib/vastai_kaalia
    printf '%s' "$id" > "$machine_id_file"
    chmod 0644 "$machine_id_file"
    echo "Restored Vast machine ID to $machine_id_file"
    echo "Current: $(cat "$machine_id_file")"
    ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
SCRIPT
  sudo chmod 0755 "$vast_machine_id"
  sudo bash -n "$vast_machine_id"
}

install_vast_power_limit_tool() {
  local vast_power_limit="/usr/local/bin/vast_power_limit"
  step "Installing persistent NVIDIA power-limit helper"
  sudo tee "$vast_power_limit" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

service="/etc/systemd/system/vast-nvidia-power-limit.service"
envfile="/etc/default/vast-nvidia-power-limit"

usage() {
  cat <<'EOF'
Usage:
  sudo vast_power_limit <watts>   Set persistent GPU power limit for all GPUs
  sudo vast_power_limit status    Show current/default/min/max/service status
  sudo vast_power_limit disable   Disable/remove persistent power limit

This intentionally keeps NVIDIA persistence mode ON with nvidia-smi -pm 1.
EOF
}

require_root() { if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then exec sudo "$0" "$@"; fi; }

status() {
  echo "== NVIDIA persistence mode =="
  if command -v nvidia-smi >/dev/null 2>&1; then
    pm_values="$(nvidia-smi --query-gpu=persistence_mode --format=csv,noheader 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    if echo "$pm_values" | grep -qi 'Disabled'; then
      echo "status: not fully enabled ($pm_values)"
    elif [[ -n "$pm_values" ]]; then
      echo "status: enabled/running ($pm_values)"
    else
      echo "status: unknown"
    fi
  else
    echo "status: unknown (nvidia-smi not found)"
  fi
  echo
  echo "== NVIDIA power limits =="
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=index,name,persistence_mode,power.draw,power.limit,power.default_limit,power.min_limit,power.max_limit --format=csv 2>/dev/null || nvidia-smi -q -d POWER || true
  else
    echo "nvidia-smi not found"
  fi
  echo
  echo "== Persistent power-limit service =="
  enabled="$(systemctl is-enabled vast-nvidia-power-limit.service 2>/dev/null || true)"
  active="$(systemctl is-active vast-nvidia-power-limit.service 2>/dev/null || true)"
  [[ -n "$enabled" ]] || enabled="not configured"
  [[ -n "$active" ]] || active="not running"
  echo "enabled: $enabled"
  echo "active: $active"
  [[ -f "$envfile" ]] && cat "$envfile" || true
}

cmd="${1:-status}"
case "$cmd" in
  status|-s|--status) status ;;
  disable|off|remove)
    require_root "$@"
    systemctl disable --now vast-nvidia-power-limit.service >/dev/null 2>&1 || true
    rm -f "$service" "$envfile"
    systemctl daemon-reload || true
    echo "Persistent NVIDIA power limit disabled/removed."
    ;;
  -h|--help|help) usage ;;
  *)
    watts="$cmd"
    case "$watts" in ''|*[!0-9]*) usage >&2; exit 2 ;; esac
    require_root "$@"
    if ! command -v nvidia-smi >/dev/null 2>&1; then echo "nvidia-smi not found" >&2; exit 1; fi
    install -d -m 0755 /etc/default
    printf 'VAST_NVIDIA_POWER_LIMIT_WATTS=%s\n' "$watts" > "$envfile"
    cat > "$service" <<'EOF_SERVICE'
[Unit]
Description=Set persistent NVIDIA GPU power limit for Vast host
After=nvidia-persistenced.service multi-user.target
Wants=nvidia-persistenced.service

[Service]
Type=oneshot
EnvironmentFile=/etc/default/vast-nvidia-power-limit
ExecStart=/usr/bin/nvidia-smi -pm 1
ExecStart=/usr/bin/nvidia-smi -pl ${VAST_NVIDIA_POWER_LIMIT_WATTS}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF_SERVICE
    systemctl daemon-reload
    systemctl enable vast-nvidia-power-limit.service >/dev/null
    systemctl restart vast-nvidia-power-limit.service
    default_limit="$(nvidia-smi --query-gpu=power.default_limit --format=csv,noheader,nounits 2>/dev/null | head -n1 | awk '{print int($1)}' || true)"
    if [[ -n "$default_limit" && "$watts" -gt "$default_limit" ]]; then
      echo "WARNING: ${watts}W is above this GPU default power limit (${default_limit}W). Verify cooling and PSU headroom."
    fi
    echo "Persistent NVIDIA power limit set to ${watts}W for all GPUs."
    echo "Persistence mode is kept ON (-pm 1)."
    ;;
esac
SCRIPT
  sudo chmod 0755 "$vast_power_limit"
  sudo bash -n "$vast_power_limit"
}

install_vast_api_key_cleanup_tool() {
  local vast_api_key_cleanup="/usr/local/bin/vast_api_key_cleanup"
  step "Installing Vast CLI/API key cleanup helper"
  sudo tee "$vast_api_key_cleanup" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
assume_yes=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes) assume_yes=1 ;;
    -h|--help) echo "Usage: sudo vast_api_key_cleanup [--yes]"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then exec sudo "$0" "$@"; fi
echo "This removes stored Vast CLI/API key config for the invoking user and root."
if [[ "$assume_yes" -ne 1 ]]; then
  read -r -p "Type CLEAN VAST API KEY to continue: " answer
  [[ "$answer" == "CLEAN VAST API KEY" ]] || { echo "Cancelled."; exit 0; }
fi
target_user="${SUDO_USER:-}"
if [[ -n "$target_user" && "$target_user" != "root" ]] && home="$(getent passwd "$target_user" | cut -d: -f6)" && [[ -n "$home" ]]; then
  rm -rf "$home/.config/vastai" "$home/.vastai" "$home/.vast"
  echo "Cleaned Vast CLI config for $target_user"
fi
rm -rf /root/.config/vastai /root/.vastai /root/.vast
echo "Cleaned Vast CLI config for root"
echo "Done. Also revoke/delete temporary API keys in the Vast.ai web UI if you created one for testing."
SCRIPT
  sudo chmod 0755 "$vast_api_key_cleanup"
  sudo bash -n "$vast_api_key_cleanup"
}


install_vast_backup_identity_tool() {
  local cmd="/usr/local/bin/vast_backup_identity"
  step "Installing Vast identity backup helper"
  sudo tee "$cmd" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
out="${1:-}"
mid="$(cat /var/lib/vastai_kaalia/machine_id 2>/dev/null || true)"
ports="$(cat /var/lib/vastai_kaalia/host_port_range 2>/dev/null || true)"
host="$(hostname 2>/dev/null || true)"
if [[ -n "$out" ]]; then
  {
    echo "# Vast identity backup - save before reinstall/wipe"
    echo "created_at=$(date -Is)"
    echo "hostname=$host"
    echo "machine_id=${mid:-MISSING}"
    echo "host_port_range=${ports:-MISSING}"
  } | tee "$out"
  echo "Saved identity backup to: $out"
else
  echo "# Vast identity backup - save before reinstall/wipe"
  echo "created_at=$(date -Is)"
  echo "hostname=$host"
  echo "machine_id=${mid:-MISSING}"
  echo "host_port_range=${ports:-MISSING}"
fi
SCRIPT
  sudo chmod 0755 "$cmd"
  sudo bash -n "$cmd"
}

install_vast_doctor_tool() {
  local cmd="/usr/local/bin/vast_doctor"
  step "Installing Vast doctor helper"
  sudo tee "$cmd" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -uo pipefail
pass=0; warn=0; fail=0
ok(){ printf '✓ %s\n' "$*"; pass=$((pass+1)); }
soft(){ printf '! %s\n' "$*"; warn=$((warn+1)); }
bad(){ printf '✗ %s\n' "$*"; fail=$((fail+1)); }
has(){ command -v "$1" >/dev/null 2>&1; }
svc(){ if systemctl list-unit-files "$1.service" --no-legend 2>/dev/null | grep -q "^$1\\.service"; then systemctl is-active --quiet "$1" && ok "$1 service active" || bad "$1 service not active"; else soft "$1 service not installed"; fi; }
echo "== Vast doctor =="; echo "Host: $(hostname)"; echo "Time: $(date -Is)"; echo
has nvidia-smi && nvidia-smi >/dev/null 2>&1 && ok "nvidia-smi works" || bad "nvidia-smi failed/missing"
if has nvidia-smi; then
  pm="$(nvidia-smi --query-gpu=persistence_mode --format=csv,noheader 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  echo "$pm" | grep -qi Disabled && soft "NVIDIA persistence mode not fully enabled ($pm)" || ok "NVIDIA persistence mode enabled/running (${pm:-unknown})"
  nvidia-smi --query-gpu=index,name,temperature.gpu,power.draw,power.limit,power.default_limit,power.max_limit --format=csv 2>/dev/null || true
fi
svc docker; svc containerd; svc vastai; svc vast_metrics; svc nvidia-persistenced
if [[ -s /var/lib/vastai_kaalia/machine_id ]]; then ok "Vast machine ID present: $(cat /var/lib/vastai_kaalia/machine_id)"; else soft "Vast machine ID missing (new identity likely)"; fi
if [[ -s /var/lib/vastai_kaalia/host_port_range ]]; then ok "Vast host port range: $(cat /var/lib/vastai_kaalia/host_port_range)"; else soft "Vast host port range missing"; fi
if systemctl is-enabled vast-nvidia-power-limit.service >/dev/null 2>&1; then ok "Persistent power-limit service enabled"; else soft "Persistent power-limit service not configured (optional)"; fi
if findmnt /var/lib/docker >/dev/null 2>&1; then
  fs="$(findmnt -no FSTYPE /var/lib/docker)"; opts="$(findmnt -no OPTIONS /var/lib/docker)"
  [[ "$fs" == xfs && "$opts" == *prjquota* ]] && ok "Docker storage XFS/prjquota" || soft "Docker storage not XFS/prjquota ($fs $opts)"
else soft "/var/lib/docker is not a separate mount"; fi
df -hT / /var/lib/docker 2>/dev/null || df -hT /
if has docker; then docker info >/dev/null 2>&1 && ok "docker info works" || bad "docker info failed"; docker system df 2>/dev/null || true; fi
if has curl && curl -I -fsS --max-time 8 https://console.vast.ai >/dev/null 2>&1; then ok "console.vast.ai reachable"; else bad "console.vast.ai not reachable"; fi
echo; echo "Summary: pass=$pass warn=$warn fail=$fail"
(( fail == 0 )) || exit 1
SCRIPT
  sudo chmod 0755 "$cmd"
  sudo bash -n "$cmd"
}

install_host_polish_tools() {
  local storage_layout disk_health vast_ready_check vast_cleanup vast_system_update vast_port_range vast_port_check burn_cleanup
  storage_layout="/usr/local/bin/storage_layout"
  disk_health="/usr/local/bin/disk_health"
  vast_ready_check="/usr/local/bin/vast_ready_check"
  vast_cleanup="/usr/local/bin/vast_cleanup"
  vast_system_update="/usr/local/bin/vast_system_update"
  vast_port_range="/usr/local/bin/vast_port_range"
  vast_port_check="/usr/local/bin/vast_port_check"
  burn_cleanup="/usr/local/bin/rig-burn-cleanup"

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

  step "Installing vast_system_update command"
  sudo tee "$vast_system_update" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo "$0" "$@"
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

echo "WARNING: vast_system_update should only run when the machine is idle/unlisted."
echo "Kernel/driver updates can restart services and may require a reboot."
echo
read -r -p "Type UPDATE IDLE MACHINE to continue: " answer
case "$answer" in
  "UPDATE IDLE MACHINE") ;;
  *) echo "Cancelled."; exit 0 ;;
esac

echo "== Current kernel / NVIDIA =="
uname -r || true
nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 | sed 's/^/NVIDIA driver: /' || true

echo
echo "== Updating apt package lists =="
apt-get update

echo
echo "== Upgrading packages, kernels and drivers =="
apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade -y

if command -v ubuntu-drivers >/dev/null 2>&1 && command -v nvidia-smi >/dev/null 2>&1; then
  echo
  echo "== Refreshing recommended Ubuntu NVIDIA driver packages =="
  ubuntu-drivers autoinstall || true
fi

echo
echo "== Cleaning unused packages =="
apt-get autoremove --purge -y
apt-get autoclean -y

echo
echo "== Updated kernel / NVIDIA =="
uname -r || true
nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 | sed 's/^/NVIDIA driver: /' || true

if [[ -f /var/run/reboot-required ]]; then
  echo
  echo "REBOOT REQUIRED: run sudo reboot when the machine is idle/unlisted."
  [[ -f /var/run/reboot-required.pkgs ]] && cat /var/run/reboot-required.pkgs || true
else
  echo
  echo "No reboot-required flag found."
fi
SCRIPT
sudo chmod 0755 "$vast_system_update"
  sudo bash -n "$vast_system_update"

  install_vast_machine_id_tool
  install_vast_backup_identity_tool
  install_vast_power_limit_tool
  install_vast_api_key_cleanup_tool
  install_vast_doctor_tool

  step "Installing Vast.ai host port helper commands"
  sudo tee "$vast_port_range" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
range="${1:-}"
if [[ -z "$range" ]]; then
  echo "Current range: $(cat /var/lib/vastai_kaalia/host_port_range 2>/dev/null || echo missing)"
  echo "Usage to change: sudo vast_port_range START-END" >&2
  echo "Example: sudo vast_port_range 63401-63800" >&2
  exit 0
fi
case "$range" in
  *-*) ;;
  *) echo "Usage: sudo vast_port_range [START-END]" >&2; echo "Example: sudo vast_port_range 63401-63800" >&2; exit 2 ;;
esac
start="${range%-*}"; end="${range#*-}"
case "$start$end" in *[!0-9]*|'') echo "Invalid range: $range" >&2; exit 2 ;; esac
if (( start < 1 || end > 65535 || start > end )); then echo "Invalid TCP/UDP port range: $range" >&2; exit 2; fi
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then echo "Re-running with sudo..."; exec sudo "$0" "$@"; fi
install -d -m 0755 /var/lib/vastai_kaalia
printf '%s
' "$range" > /var/lib/vastai_kaalia/host_port_range
chmod 0644 /var/lib/vastai_kaalia/host_port_range
summary_file="/var/lib/vast-host-installer/final-summary.txt"
if [[ -f "$summary_file" ]]; then
  tmp_summary="$(mktemp)"
  awk -v range="$range" '{ if ($0 ~ /^✓ Current: /) print "✓ Current: " range; else print $0 }' "$summary_file" > "$tmp_summary"
  cat "$tmp_summary" > "$summary_file"
  rm -f "$tmp_summary"
fi
echo "Vast.ai host port range set to: $(cat /var/lib/vastai_kaalia/host_port_range)"
echo
echo "What this is:"
echo "  Vast.ai uses /var/lib/vastai_kaalia/host_port_range to know which host ports"
echo "  it may assign/map to rented containers for services like SSH, web UIs, APIs, etc."
echo "  Example: 63401-63800 gives Vast 400 host ports to allocate."
echo
echo "Next check: sudo vast_port_check"
SCRIPT
  sudo chmod 0755 "$vast_port_range"
  sudo bash -n "$vast_port_range"

  sudo tee "$vast_port_check" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
range_file="/var/lib/vastai_kaalia/host_port_range"
if [[ ! -f "$range_file" ]]; then
  echo "Missing $range_file"
  echo "Fix: set your intended range, for example: sudo vast_port_range 63401-63800"
  exit 1
fi
range="$(tr -d '[:space:]' < "$range_file")"
start="${range%-*}"; end="${range#*-}"
case "$range" in *-*) ;; *) echo "Invalid range in $range_file: $range" >&2; exit 1 ;; esac
case "$start$end" in *[!0-9]*|'') echo "Invalid range in $range_file: $range" >&2; exit 1 ;; esac
if (( start < 1 || end > 65535 || start > end )); then echo "Invalid TCP/UDP port range in $range_file: $range" >&2; exit 1; fi
echo "== Vast.ai host port range =="
echo "$range_file: $range"
echo "Ports: $(( end - start + 1 ))"
echo
echo "What this means: Vast may map rented container services onto these host ports."
echo "Important: ports normally only show LISTEN/open when a container is actively using them."
echo "This local checker verifies the setting and local firewall/listeners; true external reachability"
echo "still depends on router/provider/firewall/public IP path."
echo
echo "== Public IP guess =="
(curl -fsS --max-time 4 https://api.ipify.org || curl -fsS --max-time 4 https://ifconfig.me || true) | sed 's/^/Public IP: /'
echo
echo "== Current listeners inside range =="
if command -v ss >/dev/null 2>&1; then
  ss -H -ltnup 2>/dev/null | awk -v s="$start" -v e="$end" '{ local=$5; n=split(local,a,":"); p=a[n]; gsub(/[^0-9]/,"",p); if (p >= s && p <= e) print }' || true
else
  echo "ss command not found"
fi
echo
echo "== Local port state summary =="
listening=0
for ((p=start; p<=end; p++)); do
  if ss -H -ltn "sport = :$p" 2>/dev/null | grep -q . || ss -H -lun "sport = :$p" 2>/dev/null | grep -q .; then
    echo "LISTEN local :$p"; listening=$((listening + 1))
  fi
done
if (( listening == 0 )); then echo "No ports in $range are listening right now. That is normal before a Vast container maps one."; fi
echo
echo "== Firewall hints =="
if command -v ufw >/dev/null 2>&1; then
  ufw_status="$(ufw status 2>/dev/null || true)"; echo "$ufw_status" | sed -n '1,12p'
  if echo "$ufw_status" | grep -qi '^Status: active'; then
    if echo "$ufw_status" | grep -Eq "${start}:${end}|${start}-${end}|${start}"; then echo "UFW appears to mention this range."; else echo "WARNING: UFW is active and no obvious rule for $range was found."; echo "Possible fix if you use UFW: sudo ufw allow ${start}:${end}/tcp && sudo ufw allow ${start}:${end}/udp"; fi
  else echo "UFW is not active."; fi
else echo "ufw not installed."; fi
echo
echo "== Result =="
echo "✓ Vast host port range file is valid: $range"
echo "Run this after a rented container starts if you want to see which ports are actually listening."
SCRIPT
  sudo chmod 0755 "$vast_port_check"
  sudo bash -n "$vast_port_check"

  step "Installing rig-burn-cleanup command"
  sudo tee "$burn_cleanup" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo "$0" "$@"
fi
auto_yes=0
case "${1:-}" in
  -y|--yes) auto_yes=1 ;;
  -h|--help)
    cat <<'EOF'
Usage: sudo rig-burn-cleanup [--yes]

Kills leftover/stuck local burn-test processes: full_burn, cpu_burn, ram_burn,
stressapptest, gpu_burn, stress-ng, and old memtester wrappers/processes.
EOF
    exit 0 ;;
  "") ;;
  *) echo "Unknown option: $1" >&2; exit 2 ;;
esac
collect_pids() {
  ps -eo pid=,ppid=,stat=,comm=,args= | awk -v self="$$" -v parent="$PPID" '
    function m(line) { return line ~ /\/usr\/local\/bin\/(full_burn|cpu_burn|ram_burn|memtester)/ || line ~ /(^|[[:space:]])(full_burn|cpu_burn|ram_burn)([[:space:]]|$)/ || line ~ /stressapptest/ || line ~ /\/opt\/gpu-burn\/gpu_burn/ || line ~ /gpu_burn -tc -m/ || line ~ /stress-ng .*--(cpu|vm)/ || line ~ /\/(usr\/sbin|sbin)\/memtester/ || line ~ /timeout .*memtester/ }
    { pid=$1; line=$0; if (pid==self || pid==parent) next; if (line ~ /rig-burn-cleanup/) next; if (m(line)) print pid; }
  ' | sort -n -u
}
print_matches() {
  ps -eo pid,ppid,stat,etimes,rss,vsz,comm,args | awk '
    function m(line) { return line ~ /\/usr\/local\/bin\/(full_burn|cpu_burn|ram_burn|memtester)/ || line ~ /(^|[[:space:]])(full_burn|cpu_burn|ram_burn)([[:space:]]|$)/ || line ~ /stressapptest/ || line ~ /\/opt\/gpu-burn\/gpu_burn/ || line ~ /gpu_burn -tc -m/ || line ~ /stress-ng .*--(cpu|vm)/ || line ~ /\/(usr\/sbin|sbin)\/memtester/ || line ~ /timeout .*memtester/ }
    NR==1 || (m($0) && $0 !~ /rig-burn-cleanup/) { print }
  '
}
mapfile -t pids < <(collect_pids)
if (( ${#pids[@]} == 0 )); then echo "No burn/stress-test leftovers found."; exit 0; fi
echo "Found burn/stress-test processes:"
print_matches
echo
if (( auto_yes == 0 )); then
  read -r -p "Type KILL BURNS to terminate these processes: " answer
  [[ "$answer" == "KILL BURNS" ]] || { echo "Cancelled."; exit 0; }
fi
echo "Sending TERM to: ${pids[*]}"
kill "${pids[@]}" 2>/dev/null || true
sleep 2
mapfile -t remaining < <(collect_pids)
if (( ${#remaining[@]} > 0 )); then
  echo "Still present; sending KILL to: ${remaining[*]}"
  kill -9 "${remaining[@]}" 2>/dev/null || true
  sleep 2
fi
mapfile -t final < <(collect_pids)
if (( ${#final[@]} > 0 )); then
  echo "WARNING: some processes still remain:" >&2
  print_matches >&2
  exit 1
fi
echo "Burn/stress-test cleanup complete."
free -h || true
SCRIPT
sudo chmod 0755 "$burn_cleanup"
  sudo bash -n "$burn_cleanup"


  success "Host polish tools installed: storage_layout, disk_health, vast_ready_check, vast_cleanup, vast_system_update, vast_machine_id, vast_backup_identity, vast_power_limit, vast_api_key_cleanup, vast_doctor, vast_port_range, vast_port_check, rig-burn-cleanup"
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

  step "Installing GPU fan mode switcher"
  sudo tee /usr/local/bin/vast_gpu_fan_mode >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo "$0" "$@"
fi

mode="${1:-status}"
no_restart=0
for arg in "${@:2}"; do
  case "$arg" in
    --no-restart) no_restart=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

install_global() {
cat >/usr/local/bin/gpu-fan.sh <<'EOF_GLOBAL'
#!/usr/bin/env bash
set -euo pipefail
export DISPLAY=:0
export XAUTHORITY=/root/.Xauthority

sleep 10

echo "global" >/run/vast-gpu-fan-mode 2>/dev/null || true

while true; do
    MAXTEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits | sort -nr | head -n1)
    GPUS=$(nvidia-settings --ctrl-display=:0 -q gpus 2>/dev/null | grep -o "gpu:[0-9]*" | sort -u || true)
    FANS=$(nvidia-settings --ctrl-display=:0 -q fans 2>/dev/null | grep -o "fan:[0-9]*" | sort -u || true)

    if [ -z "${MAXTEMP:-}" ]; then sleep 5; continue; fi
    if [ "$MAXTEMP" -lt 50 ]; then MODE="auto"; unset SPEED
    elif [ "$MAXTEMP" -lt 60 ]; then SPEED=50; MODE="manual"
    elif [ "$MAXTEMP" -lt 70 ]; then SPEED=75; MODE="manual"
    elif [ "$MAXTEMP" -lt 72 ]; then SPEED=90; MODE="manual"
    else SPEED=100; MODE="manual"; fi

    echo "$(date -Is) | global fan | max=${MAXTEMP}C -> ${MODE} ${SPEED:-} | GPUs: $GPUS | Fans: $FANS"

    for gpu in $GPUS; do
        if [ "$MODE" = "auto" ]; then
            nvidia-settings --ctrl-display=:0 -a "[$gpu]/GPUFanControlState=0" >/dev/null 2>&1 || true
        else
            nvidia-settings --ctrl-display=:0 -a "[$gpu]/GPUFanControlState=1" >/dev/null 2>&1 || true
        fi
    done
    if [ "$MODE" = "manual" ]; then
        for fan in $FANS; do
            nvidia-settings --ctrl-display=:0 -a "[$fan]/GPUTargetFanSpeed=$SPEED" >/dev/null 2>&1 || true
        done
    fi
    sleep 5
done
EOF_GLOBAL
chmod 0755 /usr/local/bin/gpu-fan.sh
}

install_per_gpu() {
cat >/usr/local/bin/gpu-fan.sh <<'EOF_PERGPU'
#!/usr/bin/env bash
set -euo pipefail
export DISPLAY=:0
export XAUTHORITY=/root/.Xauthority

state_dir="/var/lib/vast-host-installer"
map_file="$state_dir/gpu-fan-map.env"
mkdir -p "$state_dir"
echo "per-gpu" >/run/vast-gpu-fan-mode 2>/dev/null || true

speed_for_temp() {
  local temp="$1"
  if (( temp < 50 )); then echo auto
  elif (( temp < 60 )); then echo 50
  elif (( temp < 70 )); then echo 75
  elif (( temp < 72 )); then echo 90
  else echo 100
  fi
}

global_fallback_loop() {
  echo "$(date -Is) | per-gpu fan | WARNING: mapping unavailable; falling back to global curve"
  while true; do
    maxtemp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits | sort -nr | head -n1 || true)
    gpus=$(nvidia-settings --ctrl-display=:0 -q gpus 2>/dev/null | grep -o 'gpu:[0-9]*' | sort -u || true)
    fans=$(nvidia-settings --ctrl-display=:0 -q fans 2>/dev/null | grep -o 'fan:[0-9]*' | sort -u || true)
    [[ -n "${maxtemp:-}" ]] || { sleep 5; continue; }
    target=$(speed_for_temp "$maxtemp")
    for gpu in $gpus; do
      if [[ "$target" == auto ]]; then nvidia-settings --ctrl-display=:0 -a "[$gpu]/GPUFanControlState=0" >/dev/null 2>&1 || true
      else nvidia-settings --ctrl-display=:0 -a "[$gpu]/GPUFanControlState=1" >/dev/null 2>&1 || true; fi
    done
    if [[ "$target" != auto ]]; then for fan in $fans; do nvidia-settings --ctrl-display=:0 -a "[$fan]/GPUTargetFanSpeed=$target" >/dev/null 2>&1 || true; done; fi
    echo "$(date -Is) | fallback global fan | max=${maxtemp}C -> ${target}"
    sleep 5
  done
}

read_smi_fans() {
  nvidia-smi --query-gpu=index,fan.speed --format=csv,noheader,nounits | awk -F, '{gsub(/ /,"",$1); gsub(/ /,"",$2); print $1":"$2}'
}

discover_map() {
  mapfile -t gpus < <(nvidia-smi --query-gpu=index --format=csv,noheader,nounits | tr -d ' ')
  mapfile -t fans < <(nvidia-settings --ctrl-display=:0 -q fans 2>/dev/null | grep -o 'fan:[0-9]*' | sort -t: -k2,2n -u | cut -d: -f2)
  (( ${#gpus[@]} > 0 && ${#fans[@]} > 0 )) || return 1
  per=$(( ${#fans[@]} / ${#gpus[@]} ))
  (( per >= 1 )) || per=1
  (( ${#fans[@]} % ${#gpus[@]} == 0 )) || return 1

  for gpu in "${gpus[@]}"; do nvidia-settings --ctrl-display=:0 -a "[gpu:$gpu]/GPUFanControlState=1" >/dev/null 2>&1 || true; done
  set_all() { local speed="$1"; for fan in "${fans[@]}"; do nvidia-settings --ctrl-display=:0 -a "[fan:$fan]/GPUTargetFanSpeed=$speed" >/dev/null 2>&1 || true; done; }

  tmp="$(mktemp)"
  {
    echo '# Auto-discovered by gpu-fan.sh. Remove this file to re-detect.'
    echo "GPU_COUNT=${#gpus[@]}"
    echo "FAN_COUNT=${#fans[@]}"
  } >"$tmp"

  declare -A used_gpu=()
  for ((i=0; i<${#fans[@]}; i+=per)); do
    group=("${fans[@]:i:per}")
    set_all 35; sleep 4
    before="$(read_smi_fans | tr '\n' ' ')"
    for fan in "${group[@]}"; do nvidia-settings --ctrl-display=:0 -a "[fan:$fan]/GPUTargetFanSpeed=80" >/dev/null 2>&1 || true; done
    sleep 8
    after="$(read_smi_fans | tr '\n' ' ')"
    best_gpu=""; best_delta=-999
    for gpu in "${gpus[@]}"; do
      [[ -n "${used_gpu[$gpu]:-}" ]] && continue
      b=$(echo "$before" | tr ' ' '\n' | awk -F: -v g="$gpu" '$1==g{print $2}')
      a=$(echo "$after" | tr ' ' '\n' | awk -F: -v g="$gpu" '$1==g{print $2}')
      b=${b:-0}; a=${a:-0}; d=$((a-b))
      if (( d > best_delta )); then best_delta=$d; best_gpu=$gpu; fi
    done
    [[ -n "$best_gpu" && "$best_delta" -ge 15 ]] || { rm -f "$tmp"; return 1; }
    used_gpu[$best_gpu]=1
    echo "GPU_FANS_${best_gpu}=\"${group[*]}\"" >>"$tmp"
    echo "$(date -Is) | per-gpu fan discovery | fans:${group[*]} -> gpu:${best_gpu} delta:${best_delta}"
  done
  mv "$tmp" "$map_file"
}

sleep 10
if [[ ! -r "$map_file" ]]; then
  discover_map || global_fallback_loop
fi
# shellcheck disable=SC1090
source "$map_file" || global_fallback_loop

while true; do
  mapfile -t temps < <(nvidia-smi --query-gpu=index,temperature.gpu --format=csv,noheader,nounits | tr -d ' ')
  log_parts=()
  for row in "${temps[@]}"; do
    gpu="${row%%,*}"; temp="${row##*,}"
    var="GPU_FANS_${gpu}"
    fans="${!var:-}"
    [[ -n "$fans" ]] || continue
    target="$(speed_for_temp "$temp")"
    if [[ "$target" == auto ]]; then
      nvidia-settings --ctrl-display=:0 -a "[gpu:$gpu]/GPUFanControlState=0" >/dev/null 2>&1 || true
      log_parts+=("gpu${gpu}:${temp}C->auto")
    else
      nvidia-settings --ctrl-display=:0 -a "[gpu:$gpu]/GPUFanControlState=1" >/dev/null 2>&1 || true
      for fan in $fans; do nvidia-settings --ctrl-display=:0 -a "[fan:$fan]/GPUTargetFanSpeed=$target" >/dev/null 2>&1 || true; done
      log_parts+=("gpu${gpu}:${temp}C->${target}% fans:${fans// /,}")
    fi
  done
  echo "$(date -Is) | per-gpu fan | ${log_parts[*]}"
  sleep 5
done
EOF_PERGPU
chmod 0755 /usr/local/bin/gpu-fan.sh
}

case "$mode" in
  global)
    install_global
    echo "global" >/etc/vast-gpu-fan-mode
    rm -f /var/lib/vast-host-installer/gpu-fan-map.env
    ;;
  per-gpu|pergpu|smart)
    install_per_gpu
    echo "per-gpu" >/etc/vast-gpu-fan-mode
    rm -f /var/lib/vast-host-installer/gpu-fan-map.env
    ;;
  status)
    echo "configured: $(cat /etc/vast-gpu-fan-mode 2>/dev/null || echo unknown)"
    echo "running: $(cat /run/vast-gpu-fan-mode 2>/dev/null || echo unknown)"
    systemctl is-active gpu-fan.service 2>/dev/null || true
    nvidia-smi --query-gpu=index,temperature.gpu,fan.speed,utilization.gpu --format=csv,noheader,nounits 2>/dev/null || true
    exit 0
    ;;
  *)
    echo "Usage: sudo vast_gpu_fan_mode status|global|per-gpu [--no-restart]" >&2
    exit 2
    ;;
esac

bash -n /usr/local/bin/gpu-fan.sh
if [[ "$no_restart" -eq 0 ]] && systemctl list-unit-files gpu-fan.service --no-legend >/dev/null 2>&1; then
  systemctl restart gpu-fan.service
fi
echo "GPU fan mode set to: $(cat /etc/vast-gpu-fan-mode)"
SCRIPT
  sudo chmod 0755 /usr/local/bin/vast_gpu_fan_mode

  step "Installing default global aggressive fan curve"
  sudo /usr/local/bin/vast_gpu_fan_mode global --no-restart

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
