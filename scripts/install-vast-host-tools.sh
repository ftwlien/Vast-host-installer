#!/usr/bin/env bash
set -euo pipefail

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      cat <<'EOF'
Usage: sudo ./scripts/install-vast-host-tools.sh

Installs standalone Vast host helper commands for already-running Ubuntu rigs:
- vast_install_summary
- storage_layout
- vast_ready_check
- disk_health
- vast_cleanup
- vast_system_update
- cpu_burn
- ram_burn stressapptest RAM burn wrapper
- gpu_burn
- vast_install_gpu_fan_control aggressive NVIDIA GPU fan-control installer
- full_burn 7200 whole-machine RAM + CPU + GPU burn test
- rig-burn-cleanup stuck burn-test cleanup command
- vast_port_range / vast_port_check Vast.ai host port helpers
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo "$0" "$@"
fi

install -d -m 0755 /usr/local/bin /var/lib/vast-host-installer

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y smartmontools nvme-cli pciutils curl ca-certificates lsb-release mokutil
  apt-get install -y speedtest-cli || true
  apt-get install -y stress-ng stressapptest memtest86+ git build-essential nvidia-cuda-toolkit
fi

cat >/usr/local/bin/storage_layout <<'SCRIPT'
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
chmod 0755 /usr/local/bin/storage_layout

cat >/usr/local/bin/disk_health <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo "$0" "$@"
fi

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
    command -v nvme >/dev/null 2>&1 && nvme smart-log "$dev" 2>/dev/null || true
    command -v smartctl >/dev/null 2>&1 && smartctl -H -A "$dev" 2>/dev/null || true
  done
fi
SCRIPT
chmod 0755 /usr/local/bin/disk_health

cat >/usr/local/bin/vast_ready_check <<'SCRIPT'
#!/usr/bin/env bash
set -uo pipefail

pass=0; fail=0; warn=0
ok() { printf '✓ %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '✗ %s\n' "$*"; fail=$((fail+1)); }
soft() { printf '! %s\n' "$*"; warn=$((warn+1)); }
has() { command -v "$1" >/dev/null 2>&1; }
active() { systemctl is-active --quiet "$1" 2>/dev/null; }
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
chmod 0755 /usr/local/bin/vast_ready_check

cat >/usr/local/bin/vast_cleanup <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo "$0" "$@"
fi

command -v docker >/dev/null 2>&1 || { echo "docker command not found" >&2; exit 1; }

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
  "CLEAN IDLE MACHINE") docker system prune -af ;;
  *) echo "Cancelled."; exit 0 ;;
esac

echo
echo "Docker usage after cleanup:"
docker system df || true
SCRIPT
chmod 0755 /usr/local/bin/vast_cleanup

cat >/usr/local/bin/vast_system_update <<'SCRIPT'
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
chmod 0755 /usr/local/bin/vast_system_update

cat >/usr/local/bin/cpu_burn <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
seconds="${1:-60}"
case "$seconds" in ''|*[!0-9]*) echo "Usage: cpu_burn [seconds]" >&2; echo "Example: cpu_burn 60" >&2; exit 2;; esac
exec stress-ng --cpu 0 --cpu-method matrixprod --verify --metrics-brief --timeout "${seconds}s"
SCRIPT
chmod 0755 /usr/local/bin/cpu_burn

cat >/usr/local/bin/ram_burn <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
seconds="${1:-60}"
case "$seconds" in ''|*[!0-9]*) echo "Usage: ram_burn [seconds]" >&2; echo "Example: ram_burn 7200" >&2; exit 2;; esac
if ! command -v stressapptest >/dev/null 2>&1; then
  echo "stressapptest command not found. Install package: sudo apt-get install -y stressapptest" >&2
  exit 1
fi
# stressapptest works best with enough privilege to lock/hammer memory consistently.
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
  if (( percent_target < available_target )); then
    memory_mb=$percent_target
  else
    memory_mb=$available_target
  fi
fi
max_mb=$(( available_mb - 2048 ))
if (( memory_mb > max_mb )); then
  memory_mb=$max_mb
fi
if (( memory_mb < 1024 )); then
  echo "Not enough available memory for ram_burn (${memory_mb}M calculated; total=${total_mb}M available=${available_mb}M reserve=${reserve_mb}M)" >&2
  exit 1
fi
memory_gib="$(awk -v mb="$memory_mb" 'BEGIN {printf "%.1f", mb/1024}')"
log_dir="${RAM_BURN_LOG_DIR:-${SUDO_USER:+/home/$SUDO_USER}/burn-logs}"
if [[ -z "$log_dir" || "$log_dir" == "/burn-logs" ]]; then
  log_dir="${HOME}/burn-logs"
fi
mkdir -p "$log_dir"
if [[ -n "${SUDO_USER:-}" && -d "/home/$SUDO_USER" ]]; then
  chown "$SUDO_USER:$SUDO_USER" "$log_dir" 2>/dev/null || true
fi
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
  elapsed="$(ps -o etimes= -p "$sap_pid" 2>/dev/null | tr -d ' ' || echo 0)"
  elapsed="${elapsed:-0}"
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
SCRIPT
chmod 0755 /usr/local/bin/ram_burn
# Compatibility shim: old command name now runs stressapptest-backed RAM burn.
cat >/usr/local/bin/memtester <<'SCRIPT'
#!/usr/bin/env bash
exec /usr/local/bin/ram_burn "$@"
SCRIPT
chmod 0755 /usr/local/bin/memtester

cat >/usr/local/bin/vast_install_gpu_burn <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo "$0" "$@"
fi

if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi >/dev/null 2>&1; then
  echo "NVIDIA is not ready. Fix nvidia-smi before installing gpu_burn." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  apt-get install -y git build-essential nvidia-cuda-toolkit stress-ng stressapptest memtest86+
fi

workdir="/tmp/gpu-burn-build"
install_dir="/opt/gpu-burn"
rm -rf "$workdir"
git clone https://github.com/wilicc/gpu-burn.git "$workdir"
make -C "$workdir"
test -x "$workdir/gpu_burn"

rm -rf "$install_dir"
install -d -m 0755 "$install_dir"
cp -a "$workdir"/. "$install_dir"/
chmod -R a+rX "$install_dir"
chmod 0755 "$install_dir/gpu_burn"

cat >/usr/local/bin/gpu_burn <<EOF
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
chmod 0755 /usr/local/bin/gpu_burn


if command -v cpu_burn >/dev/null 2>&1; then
  cat >/usr/local/bin/full_burn <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
seconds="${1:-7200}"
case "$seconds" in ''|*[!0-9]*) echo "Usage: full_burn [seconds]" >&2; echo "Example: full_burn 7200" >&2; exit 2;; esac
log_dir="${FULL_BURN_LOG_DIR:-$HOME/burn-logs}"
mkdir -p "$log_dir"
log_file="$log_dir/full_burn-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$log_file") 2>&1
echo "full_burn log: $log_file"
echo "Starting CPU + GPU + RAM burn for ${seconds}s"
echo "RAM target defaults: FULL_BURN_RAM_PERCENT=${FULL_BURN_RAM_PERCENT:-90}, FULL_BURN_RAM_RESERVE_MB=${FULL_BURN_RAM_RESERVE_MB:-8192}"
cpu_burn "$seconds" & cpu_pid=$!
gpu_burn -tc -m 100% "$seconds" & gpu_pid=$!
ram_pressure_pid=""
if command -v ram_burn >/dev/null 2>&1; then
  sudo RAM_BURN_PERCENT="${FULL_BURN_RAM_PERCENT:-90}" RAM_BURN_RESERVE_MB="${FULL_BURN_RAM_RESERVE_MB:-8192}" ram_burn "$seconds" & ram_pressure_pid=$!
else
  echo "ram_burn not found; running CPU + GPU only" >&2
fi
cleanup() {
  kill "$cpu_pid" "$gpu_pid" ${ram_pressure_pid:+"$ram_pressure_pid"} >/dev/null 2>&1 || true
  wait "$cpu_pid" >/dev/null 2>&1 || true
  wait "$gpu_pid" >/dev/null 2>&1 || true
  [[ -n "$ram_pressure_pid" ]] && wait "$ram_pressure_pid" >/dev/null 2>&1 || true
}
trap 'cleanup; exit 130' INT TERM
cpu_status=0; gpu_status=0; ram_status=0
wait "$cpu_pid" || cpu_status=$?
wait "$gpu_pid" || gpu_status=$?
[[ -n "$ram_pressure_pid" ]] && wait "$ram_pressure_pid" || ram_status=$?
if [[ "$cpu_status" -ne 0 || "$gpu_status" -ne 0 || "$ram_status" -ne 0 ]]; then
  echo "full_burn finished with errors: cpu=${cpu_status}, gpu=${gpu_status}, ram=${ram_status}" >&2
  exit 1
fi
echo "full_burn completed successfully"
echo "Log saved to: $log_file"
EOF
  chmod 0755 /usr/local/bin/full_burn
fi

bash -n /usr/local/bin/gpu_burn
[[ -x /usr/local/bin/full_burn ]] && bash -n /usr/local/bin/full_burn || true
rm -rf "$workdir"
echo "gpu_burn installed. Test with: gpu_burn -tc -m 100% 60"
echo "Run vast_install_summary again to refresh the report."
SCRIPT
chmod 0755 /usr/local/bin/vast_install_gpu_burn

# Install gpu_burn/full_burn by default so this one installer gives the full toolkit.
if ! command -v gpu_burn >/dev/null 2>&1 || [[ ! -x /usr/local/bin/full_burn ]]; then
  /usr/local/bin/vast_install_gpu_burn
fi

# Always refresh full_burn so wrapper logic updates without rebuilding gpu-burn.
if command -v gpu_burn >/dev/null 2>&1 && command -v cpu_burn >/dev/null 2>&1; then
  cat >/usr/local/bin/full_burn <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
seconds="${1:-7200}"
case "$seconds" in ''|*[!0-9]*) echo "Usage: full_burn [seconds]" >&2; echo "Example: full_burn 7200" >&2; exit 2;; esac
log_dir="${FULL_BURN_LOG_DIR:-$HOME/burn-logs}"
mkdir -p "$log_dir"
log_file="$log_dir/full_burn-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$log_file") 2>&1
echo "full_burn log: $log_file"
echo "Starting CPU + GPU + RAM burn for ${seconds}s"
echo "RAM target defaults: FULL_BURN_RAM_PERCENT=${FULL_BURN_RAM_PERCENT:-90}, FULL_BURN_RAM_RESERVE_MB=${FULL_BURN_RAM_RESERVE_MB:-8192}"
cpu_burn "$seconds" & cpu_pid=$!
gpu_burn -tc -m 100% "$seconds" & gpu_pid=$!
ram_pressure_pid=""
if command -v ram_burn >/dev/null 2>&1; then
  sudo RAM_BURN_PERCENT="${FULL_BURN_RAM_PERCENT:-90}" RAM_BURN_RESERVE_MB="${FULL_BURN_RAM_RESERVE_MB:-8192}" ram_burn "$seconds" & ram_pressure_pid=$!
else
  echo "ram_burn not found; running CPU + GPU only" >&2
fi
cleanup() {
  kill "$cpu_pid" "$gpu_pid" ${ram_pressure_pid:+"$ram_pressure_pid"} >/dev/null 2>&1 || true
  wait "$cpu_pid" >/dev/null 2>&1 || true
  wait "$gpu_pid" >/dev/null 2>&1 || true
  [[ -n "$ram_pressure_pid" ]] && wait "$ram_pressure_pid" >/dev/null 2>&1 || true
}
trap 'cleanup; exit 130' INT TERM
cpu_status=0; gpu_status=0; ram_status=0
wait "$cpu_pid" || cpu_status=$?
wait "$gpu_pid" || gpu_status=$?
[[ -n "$ram_pressure_pid" ]] && wait "$ram_pressure_pid" || ram_status=$?
if [[ "$cpu_status" -ne 0 || "$gpu_status" -ne 0 || "$ram_status" -ne 0 ]]; then
  echo "full_burn finished with errors: cpu=${cpu_status}, gpu=${gpu_status}, ram=${ram_status}" >&2
  exit 1
fi
echo "full_burn completed successfully"
echo "Log saved to: $log_file"
EOF
  chmod 0755 /usr/local/bin/full_burn
fi

cat >/usr/local/bin/vast_port_range <<'SCRIPT'
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
printf '%s\n' "$range" > /var/lib/vastai_kaalia/host_port_range
chmod 0644 /var/lib/vastai_kaalia/host_port_range
echo "Vast.ai host port range set to: $(cat /var/lib/vastai_kaalia/host_port_range)"
echo
echo "What this is:"
echo "  Vast.ai uses /var/lib/vastai_kaalia/host_port_range to know which host ports"
echo "  it may assign/map to rented containers for services like SSH, web UIs, APIs, etc."
echo "  Example: 63401-63800 gives Vast 400 host ports to allocate."
echo
echo "Next check: sudo vast_port_check"
SCRIPT
chmod 0755 /usr/local/bin/vast_port_range

cat >/usr/local/bin/vast_port_check <<'SCRIPT'
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
chmod 0755 /usr/local/bin/vast_port_check

# Do not overwrite an existing Vast.ai port range automatically.
# Operators can change it explicitly with: sudo vast_port_range START-END

# Install rig-monitor for the operator user if it is not already present.
install_rig_monitor_for_operator() {
  local target_user target_home repo_dir
  target_user="${SUDO_USER:-}"
  if [[ -z "$target_user" || "$target_user" == "root" ]]; then
    target_user="$(logname 2>/dev/null || true)"
  fi
  if [[ -z "$target_user" || "$target_user" == "root" ]]; then
    target_user="$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1; exit}' /etc/passwd)"
  fi
  [[ -n "$target_user" ]] || return 0
  target_home="$(getent passwd "$target_user" | cut -d: -f6)"
  [[ -n "$target_home" && -d "$target_home" ]] || return 0
  repo_dir="$target_home/rig-monitor"

  if [[ -d "$repo_dir/.git" ]]; then
    sudo -H -u "$target_user" git -C "$repo_dir" pull --ff-only || true
  elif [[ ! -d "$repo_dir" ]]; then
    sudo -H -u "$target_user" git clone https://github.com/ftwlien/rig-monitor.git "$repo_dir" || return 0
  fi

  if [[ -x "$repo_dir/scripts/install.sh" ]]; then
    sudo -H -u "$target_user" bash "$repo_dir/scripts/install.sh" || true
  fi
}
if ! command -v rig-monitor >/dev/null 2>&1; then
  install_rig_monitor_for_operator
fi

cat >/usr/local/bin/rig-burn-cleanup <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then echo "Re-running with sudo..."; exec sudo "$0" "$@"; fi
auto_yes=0
case "${1:-}" in -y|--yes) auto_yes=1 ;; -h|--help) echo "Usage: sudo rig-burn-cleanup [--yes]"; exit 0 ;; "") ;; *) echo "Unknown option: $1" >&2; exit 2 ;; esac
collect_pids() { ps -eo pid=,ppid=,stat=,comm=,args= | awk -v self="$$" -v parent="$PPID" 'function m(line) { return line ~ /\/usr\/local\/bin\/(full_burn|cpu_burn|ram_burn|memtester)/ || line ~ /(^|[[:space:]])(full_burn|cpu_burn|ram_burn)([[:space:]]|$)/ || line ~ /stressapptest/ || line ~ /\/opt\/gpu-burn\/gpu_burn/ || line ~ /gpu_burn -tc -m/ || line ~ /stress-ng .*--(cpu|vm)/ || line ~ /\/(usr\/sbin|sbin)\/memtester/ || line ~ /timeout .*memtester/ } { pid=$1; line=$0; if (pid==self || pid==parent) next; if (line ~ /rig-burn-cleanup/) next; if (m(line)) print pid; }' | sort -n -u; }
print_matches() { ps -eo pid,ppid,stat,etimes,rss,vsz,comm,args | awk 'function m(line) { return line ~ /\/usr\/local\/bin\/(full_burn|cpu_burn|ram_burn|memtester)/ || line ~ /(^|[[:space:]])(full_burn|cpu_burn|ram_burn)([[:space:]]|$)/ || line ~ /stressapptest/ || line ~ /\/opt\/gpu-burn\/gpu_burn/ || line ~ /gpu_burn -tc -m/ || line ~ /stress-ng .*--(cpu|vm)/ || line ~ /\/(usr\/sbin|sbin)\/memtester/ || line ~ /timeout .*memtester/ } NR==1 || (m($0) && $0 !~ /rig-burn-cleanup/) { print }'; }
mapfile -t pids < <(collect_pids)
if (( ${#pids[@]} == 0 )); then echo "No burn/stress-test leftovers found."; exit 0; fi
echo "Found burn/stress-test processes:"; print_matches; echo
if (( auto_yes == 0 )); then read -r -p "Type KILL BURNS to terminate these processes: " answer; [[ "$answer" == "KILL BURNS" ]] || { echo "Cancelled."; exit 0; }; fi
echo "Sending TERM to: ${pids[*]}"; kill "${pids[@]}" 2>/dev/null || true; sleep 2
mapfile -t remaining < <(collect_pids)
if (( ${#remaining[@]} > 0 )); then echo "Still present; sending KILL to: ${remaining[*]}"; kill -9 "${remaining[@]}" 2>/dev/null || true; sleep 2; fi
mapfile -t final < <(collect_pids)
if (( ${#final[@]} > 0 )); then echo "WARNING: some processes still remain:" >&2; print_matches >&2; exit 1; fi
echo "Burn/stress-test cleanup complete."; free -h || true
SCRIPT
chmod 0755 /usr/local/bin/rig-burn-cleanup

cat >/usr/local/bin/vast_install_gpu_fan_control <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo "$0" "$@"
fi

step() { printf '\n==> %s\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

echo "== Aggressive Vast.ai GPU fan control installer =="
echo
echo "This installs headless NVIDIA Xorg plus gpu-fan.service."
echo "Fan curve: <50°C auto, <60°C 50%, <70°C 75%, <72°C 90%, >=72°C 100%."
echo

if ! command -v nvidia-smi >/dev/null 2>&1; then
  die "nvidia-smi is missing. Install NVIDIA drivers first, then rerun this command."
fi
if ! nvidia-smi >/dev/null 2>&1; then
  die "NVIDIA is not ready; nvidia-smi failed. Fix the driver before installing fan control."
fi
if ! command -v apt-get >/dev/null 2>&1; then
  die "This helper currently supports apt-based Ubuntu/Debian systems."
fi

export DEBIAN_FRONTEND=noninteractive

step "Installing Xorg/nvidia-settings runtime dependencies"
apt-get update
apt-get install -y xserver-xorg-core nvidia-settings libxv1

step "Ensuring NVIDIA Xorg config exposes all GPUs and fan controls"
if command -v nvidia-xconfig >/dev/null 2>&1; then
  nvidia-xconfig -a --cool-bits=28 --allow-empty-initial-configuration --enable-all-gpus || true
else
  echo "WARNING: nvidia-xconfig not found; continuing because some driver packages omit it." >&2
fi

step "Installing headless NVIDIA Xorg service"
cat >/etc/systemd/system/nvidia-xorg.service <<'EOF'
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
cat >/usr/local/bin/gpu-fan.sh <<'EOF'
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
chmod 0755 /usr/local/bin/gpu-fan.sh
bash -n /usr/local/bin/gpu-fan.sh

step "Installing GPU fan control service"
cat >/etc/systemd/system/gpu-fan.service <<'EOF'
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

systemd-analyze verify /etc/systemd/system/nvidia-xorg.service /etc/systemd/system/gpu-fan.service >/dev/null
systemctl daemon-reload
systemctl enable nvidia-xorg.service gpu-fan.service >/dev/null

step "Starting headless Xorg and fan control"
if ! systemctl is-active --quiet nvidia-xorg.service; then
  systemctl start nvidia-xorg.service
fi
systemctl restart gpu-fan.service

sleep 15
systemctl is-active --quiet nvidia-xorg.service || die "nvidia-xorg.service did not become active"
systemctl is-active --quiet gpu-fan.service || die "gpu-fan.service did not become active"
DISPLAY=:0 XAUTHORITY=/root/.Xauthority nvidia-settings -q gpus -q fans >/dev/null 2>&1 || die "nvidia-settings cannot see GPUs/fans on DISPLAY=:0"

echo
echo "Aggressive Vast.ai GPU fan control installed and running."
echo "Check it with: systemctl status gpu-fan.service"
SCRIPT
chmod 0755 /usr/local/bin/vast_install_gpu_fan_control

summary_file="/var/lib/vast-host-installer/final-summary.txt"
install -d -m 0755 /var/lib/vast-host-installer
burn_cmds=()
command -v cpu_burn >/dev/null 2>&1 && burn_cmds+=("cpu_burn")
command -v ram_burn >/dev/null 2>&1 && burn_cmds+=("ram_burn")
command -v gpu_burn >/dev/null 2>&1 && burn_cmds+=("gpu_burn")
command -v full_burn >/dev/null 2>&1 && burn_cmds+=("full_burn")
quick=()
command -v cpu_burn >/dev/null 2>&1 && quick+=("cpu_burn 60")
command -v ram_burn >/dev/null 2>&1 && quick+=("sudo ram_burn 60")
command -v gpu_burn >/dev/null 2>&1 && quick+=("gpu_burn -tc -m 100% 60")
if command -v full_burn >/dev/null 2>&1; then
  quick+=("full_burn 7200 - Full burn: RAM + CPU + GPU together")
fi
quick+=("Tip: 60 = seconds. Use 7200 for a 2-hour burn-in.")
polish=(
  "storage_layout - Show disk layout and Docker storage"
  "sudo vast_ready_check - Full Vast host readiness check"
  "sudo disk_health - Disk health and filesystem check"
  "sudo docker system df - Docker disk usage"
  "sudo vast_system_update - Safe system update helper"
  "sudo vast_cleanup - Clean idle/unlisted host leftovers"
  "sudo vast_port_check - Verify Vast host ports"
  "sudo rig-burn-cleanup - Kill stuck burn-test leftovers"
)
command -v gpu_burn >/dev/null 2>&1 || polish+=("sudo vast_install_gpu_burn - Install/rebuild GPU burn tool")
systemctl list-unit-files gpu-fan.service --no-legend 2>/dev/null | grep -q '^gpu-fan\.service' || polish+=("sudo vast_install_gpu_fan_control - Install aggressive GPU fan control")
command -v rig-monitor >/dev/null 2>&1 && polish+=("rig-monitor - Open rig monitor")
{
  echo "VAST HOST - PHASE 3 COMPLETE - VAST SETUP FINISHED"
  echo "Generated: $(date -Is)"
  echo
  echo "What was done - full install report"
  if command -v rig-monitor >/dev/null 2>&1; then
    echo "✓ rig-monitor command installed"
  fi
  if (( ${#burn_cmds[@]} > 0 )); then
    joined="${burn_cmds[*]}"
    echo "✓ Stress-test commands installed: ${joined// /, }"
  else
    echo "✓ Stress-test commands missing"
    echo "✓ Install: curl -fsSL https://raw.githubusercontent.com/ftwlien/Vast-host-installer/main/scripts/install-vast-host-tools.sh | sudo bash"
  fi
  echo "✓ Host polish commands installed"
  echo
  echo "Vast.ai host port range"
  echo "✓ Current: $(cat /var/lib/vastai_kaalia/host_port_range 2>/dev/null || echo missing)"
  echo "✓ Show current: cat /var/lib/vastai_kaalia/host_port_range"
  echo "✓ Change only if needed: sudo vast_port_range START-END"
  echo "✓ Check: sudo vast_port_check"
  echo
  echo "Quick stress-test commands"
  for line in "${quick[@]}"; do echo "✓ $line"; done
  echo
  echo "Useful host polish commands"
  for line in "${polish[@]}"; do echo "✓ $line"; done
  echo
  echo "Optional next steps - Vast CLI"
  echo "vastai --help"
  echo "vastai set api-key YOUR_API_KEY"
  echo "vastai show user"
  echo "vastai show machines"
  echo "vastai self-test machine YOUR_MACHINE_ID"
  echo "vastai self-test machine YOUR_MACHINE_ID --ignore-requirements"
  echo "More CLI examples: https://docs.vast.ai/cli/hello-world"
} > "$summary_file"
chmod 0644 "$summary_file"

cat >/usr/local/bin/vast_install_summary <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
summary_file="/var/lib/vast-host-installer/final-summary.txt"
if [[ ! -r "$summary_file" ]]; then
  echo "No final Vast Host install summary found at $summary_file" >&2
  echo "Finish Phase 3 first, then run vast_install_summary again." >&2
  exit 1
fi

if [[ -t 1 ]]; then
  printf '\033[H\033[2J\033[3J'
  C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[1;32m'; C_SKY='\033[1;38;5;45m'; C_GRAY='\033[1;38;5;244m'; C_WHITE='\033[1;37m'
else
  C_RESET=''; C_BOLD=''; C_GREEN=''; C_SKY=''; C_GRAY=''; C_WHITE=''
fi

_box_line() { local c="$1" n="$2" out=""; while [[ ${#out} -lt "$n" ]]; do out+="$c"; done; printf '%s' "$out"; }
hero_banner() {
  printf '\n%b' "$C_SKY$C_BOLD"
  cat <<'BANNER'
██╗   ██╗ █████╗ ███████╗████████╗    ██╗  ██╗ ██████╗ ███████╗████████╗
██║   ██║██╔══██╗██╔════╝╚══██╔══╝    ██║  ██║██╔═══██╗██╔════╝╚══██╔══╝
██║   ██║███████║███████╗   ██║       ███████║██║   ██║███████╗   ██║
╚██╗ ██╔╝██╔══██║╚════██║   ██║       ██╔══██║██║   ██║╚════██║   ██║
 ╚████╔╝ ██║  ██║███████║   ██║       ██║  ██║╚██████╔╝███████║   ██║
  ╚═══╝  ╚═╝  ╚═╝╚══════╝   ╚═╝       ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝
BANNER
  printf '%b' "$C_RESET"
  printf '%bFast RAM ISO · Ubuntu 22.04 · NVIDIA Open Driver · Vast.ai Host Setup%b\n\n' "$C_SKY$C_BOLD" "$C_RESET"
}
success_banner() {
  local title="$*" width=84 left right
  left=$(( (width - ${#title}) / 2 )); right=$(( width - left - ${#title} ))
  printf '\n%b╭%s╮%b\n' "$C_GREEN$C_BOLD" "$(_box_line '═' "$width")" "$C_RESET"
  printf '%b│%*s│%b\n' "$C_GREEN$C_BOLD" "$width" "" "$C_RESET"
  printf '%b│%b%*s%b%s%b%*s%b│%b\n' "$C_GREEN$C_BOLD" "$C_RESET" "$left" "" "$C_GREEN$C_BOLD" "$title" "$C_RESET" "$right" "" "$C_GREEN$C_BOLD" "$C_RESET"
  printf '%b│%*s│%b\n' "$C_GREEN$C_BOLD" "$width" "" "$C_RESET"
  printf '%b╰%s╯%b\n' "$C_GREEN$C_BOLD" "$(_box_line '═' "$width")" "$C_RESET"
}
install_report_box() {
  local title="$1"; shift || true
  local width=84 inner line prefix wrapped chunk
  inner=$((width - 4))
  printf '\n%b╭─ %s ' "$C_SKY$C_BOLD" "$title"
  local used=$(( ${#title} + 4 ))
  printf '%s╮%b\n' "$(_box_line '─' $(( width - used )))" "$C_RESET"
  if [[ "$#" -eq 0 ]]; then
    printf '%b│%b %-*s %b│%b\n' "$C_SKY$C_BOLD" "$C_GRAY" "$inner" "No entries" "$C_SKY$C_BOLD" "$C_RESET"
  else
    for line in "$@"; do
      prefix="✓ "
      wrapped="$line"
      while true; do
        local available=$((inner - ${#prefix}))
        if [[ ${#wrapped} -le $available ]]; then
          printf '%b│%b %s%b%-*s %b│%b\n' "$C_SKY$C_BOLD" "$C_GREEN" "$prefix" "${C_LINE:-$C_WHITE$C_BOLD}" "$available" "$wrapped" "$C_SKY$C_BOLD" "$C_RESET"
          break
        fi
        chunk="${wrapped:0:$available}"
        if [[ "$chunk" == *" "* ]]; then
          chunk="${chunk% *}"
          [[ -n "$chunk" ]] || chunk="${wrapped:0:$available}"
        fi
        printf '%b│%b %s%b%-*s %b│%b\n' "$C_SKY$C_BOLD" "$C_GREEN" "$prefix" "${C_LINE:-$C_WHITE$C_BOLD}" "$available" "$chunk" "$C_SKY$C_BOLD" "$C_RESET"
        wrapped="${wrapped:${#chunk}}"
        wrapped="${wrapped# }"
        prefix="  "
      done
    done
  fi
  printf '%b╰%s╯%b\n' "$C_SKY$C_BOLD" "$(_box_line '─' "$width")" "$C_RESET"
}

done_lines=(); port_lines=(); quick_lines=(); polish_lines=(); cli_lines=(); section=""
while IFS= read -r line; do
  case "$line" in
    "What was done - full install report") section="done"; continue ;;
    "Vast.ai host port range") section="port"; continue ;;
    "Quick stress-test commands") section="quick"; continue ;;
    "Useful host polish commands") section="polish"; continue ;;
    "Optional next steps - Vast CLI") section="cli"; continue ;;
    "VAST HOST - "*|"Generated: "*|"") continue ;;
  esac
  line="${line#✓ }"
  case "$section" in
    done) done_lines+=("$line") ;;
    port) port_lines+=("$line") ;;
    quick) quick_lines+=("$line") ;;
    polish) polish_lines+=("$line") ;;
    cli) cli_lines+=("$line") ;;
  esac
done < "$summary_file"

hero_banner
success_banner "PHASE 3 COMPLETE - VAST SETUP FINISHED"
install_report_box "What was done - full install report" "${done_lines[@]}"
if [[ "${#port_lines[@]}" -gt 0 ]]; then
  install_report_box "Vast.ai host port range" "${port_lines[@]}"
fi
if [[ "${#quick_lines[@]}" -gt 0 ]]; then
  install_report_box "Quick stress-test commands" "${quick_lines[@]}"
fi
if [[ "${#polish_lines[@]}" -gt 0 ]]; then
  install_report_box "Useful host polish commands" "${polish_lines[@]}"
fi
if [[ "${#cli_lines[@]}" -gt 0 ]]; then
  install_report_box "Optional next steps - Vast CLI" "${cli_lines[@]}"
fi
SCRIPT
chmod 0755 /usr/local/bin/vast_install_summary

for cmd in storage_layout disk_health vast_ready_check vast_cleanup vast_system_update vast_install_gpu_burn vast_install_gpu_fan_control vast_port_range vast_port_check rig-burn-cleanup vast_install_summary; do
  bash -n "/usr/local/bin/$cmd"
done
bash -n /usr/local/bin/cpu_burn /usr/local/bin/ram_burn /usr/local/bin/memtester
[[ -x /usr/local/bin/full_burn ]] && bash -n /usr/local/bin/full_burn || true


# Repair a common Vast metrics install issue: launcher exists but is not executable.
metrics_launcher="/var/lib/vastai_kaalia/latest/launch_metrics_pusher.sh"
if [[ -e "$metrics_launcher" && ! -x "$metrics_launcher" ]]; then
  chmod 0755 "$metrics_launcher" || true
  systemctl restart vast_metrics.service 2>/dev/null || true
fi

cat >/var/lib/vast-host-installer/host-tools-installed.txt <<EOF
installed_at=$(date -Is)
commands=vast_install_summary storage_layout vast_ready_check disk_health vast_cleanup vast_system_update vast_install_gpu_burn vast_install_gpu_fan_control vast_port_range vast_port_check rig-burn-cleanup cpu_burn ram_burn memtester gpu_burn full_burn
EOF

echo "Installed Vast host tools. Run: vast_install_summary"
