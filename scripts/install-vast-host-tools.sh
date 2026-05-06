#!/usr/bin/env bash
set -euo pipefail

WITH_BURN_TOOLS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-burn-tools)
      WITH_BURN_TOOLS=1
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: sudo ./scripts/install-vast-host-tools.sh [--with-burn-tools]

Installs standalone Vast host helper commands for already-running rigs:
- vast_install_summary
- storage_layout
- vast_ready_check
- disk_health
- vast_cleanup

Optional:
- --with-burn-tools installs cpu_burn, memtester package, and full_burn when gpu_burn exists.
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
  if [[ "$WITH_BURN_TOOLS" -eq 1 ]]; then
    apt-get install -y stress-ng memtester memtest86+
  fi
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
check_service vast_metrics
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

if [[ "$WITH_BURN_TOOLS" -eq 1 ]]; then
  cat >/usr/local/bin/cpu_burn <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
seconds="${1:-60}"
case "$seconds" in ''|*[!0-9]*) echo "Usage: cpu_burn [seconds]" >&2; echo "Example: cpu_burn 60" >&2; exit 2;; esac
exec stress-ng --cpu 0 --cpu-method matrixprod --verify --metrics-brief --timeout "${seconds}s"
SCRIPT
  chmod 0755 /usr/local/bin/cpu_burn

  cat >/usr/local/bin/memtester <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
seconds="${1:-60}"
case "$seconds" in ''|*[!0-9]*) echo "Usage: memtester [seconds]" >&2; echo "Example: memtester 60" >&2; exit 2;; esac
memory_mb="${MEMTESTER_MB:-}"
if [[ -z "$memory_mb" ]]; then
  available_mb="$(awk '/MemAvailable:/ {printf "%d", $2 / 1024}' /proc/meminfo)"
  memory_mb=$(( available_mb * 80 / 100 ))
fi
(( memory_mb >= 64 )) || { echo "Not enough available memory for memtester (${memory_mb}M calculated)" >&2; exit 1; }
exec timeout --foreground "${seconds}s" /usr/bin/memtester "${memory_mb}M" 1
SCRIPT
  chmod 0755 /usr/local/bin/memtester

  if command -v gpu_burn >/dev/null 2>&1; then
    cat >/usr/local/bin/full_burn <<'SCRIPT'
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
cpu_burn "$seconds" & cpu_pid=$!
gpu_burn -tc -m 100% "$seconds" & gpu_pid=$!
ram_pressure_pid=""
if command -v stress-ng >/dev/null 2>&1; then
  stress-ng --vm 0 --vm-bytes 50% --verify --metrics-brief --timeout "${seconds}s" & ram_pressure_pid=$!
fi
cleanup() { kill "$cpu_pid" "$gpu_pid" ${ram_pressure_pid:+"$ram_pressure_pid"} >/dev/null 2>&1 || true; }
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
SCRIPT
    chmod 0755 /usr/local/bin/full_burn
  fi
fi

cat >/usr/local/bin/vast_install_summary <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [[ -t 1 ]]; then
  C_RESET='\033[0m'; C_BOLD='\033[1m'; C_GREEN='\033[1;32m'; C_SKY='\033[1;38;5;45m'; C_GRAY='\033[1;38;5;244m'
else
  C_RESET=''; C_BOLD=''; C_GREEN=''; C_SKY=''; C_GRAY=''
fi
_box_line() { local c="$1" n="$2" out=""; while [[ ${#out} -lt "$n" ]]; do out+="$c"; done; printf '%s' "$out"; }
hero_banner() {
  printf '\n%b' "$C_SKY$C_BOLD"
  cat <<'EOF'
██╗   ██╗ █████╗ ███████╗████████╗    ██╗  ██╗ ██████╗ ███████╗████████╗
██║   ██║██╔══██╗██╔════╝╚══██╔══╝    ██║  ██║██╔═══██╗██╔════╝╚══██╔══╝
██║   ██║███████║███████╗   ██║       ███████║██║   ██║███████╗   ██║
╚██╗ ██╔╝██╔══██║╚════██║   ██║       ██╔══██║██║   ██║╚════██║   ██║
 ╚████╔╝ ██║  ██║███████║   ██║       ██║  ██║╚██████╔╝███████║   ██║
  ╚═══╝  ╚═╝  ╚═╝╚══════╝   ╚═╝       ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝
EOF
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
  local title="$1" line chunk prefix color width=84 text_width=78
  shift; color="$C_SKY$C_BOLD"
  printf '\n%b╭─ %-76.76s ╮%b\n' "$color" "$title" "$C_RESET"
  for line in "$@"; do
    prefix="✓"
    while [[ -n "$line" ]]; do
      chunk="${line:0:$text_width}"; line="${line:$text_width}"
      printf '%b│%b %b%s%b %-78s %b│%b\n' "$color" "$C_RESET" "$C_GREEN$C_BOLD" "$prefix" "$C_RESET" "$chunk" "$color" "$C_RESET"
      prefix=" "
    done
  done
  printf '%b╰%s╯%b\n\n' "$color" "$(_box_line '─' "$width")" "$C_RESET"
}
command_list_box() {
  local line
  printf '\n%b╭─ NEXT COMMANDS ────────────────────────────────────────────────────╮%b\n' "$C_GREEN$C_BOLD" "$C_RESET"
  for line in "$@"; do
    printf '%b│%b %b%-66.66s%b %b│%b\n' "$C_GREEN$C_BOLD" "$C_RESET" "$C_GREEN$C_BOLD" "$line" "$C_RESET" "$C_GREEN$C_BOLD" "$C_RESET"
  done
  printf '%b╰─────────────────────────────────────────────────────────────────────╯%b\n\n' "$C_GREEN$C_BOLD" "$C_RESET"
}

lines=(
  "Existing rig tools package installed"
  "Host: $(hostname)"
  "Generated: $(date -Is)"
)
command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1 && lines+=("NVIDIA driver working") || lines+=("NVIDIA driver not verified")
systemctl is-active --quiet docker 2>/dev/null && lines+=("Docker service active") || lines+=("Docker service not active")
systemctl is-active --quiet vastai 2>/dev/null && lines+=("Vast service active") || lines+=("Vast service not active or not installed")
if findmnt /var/lib/docker >/dev/null 2>&1; then
  fs="$(findmnt -no FSTYPE /var/lib/docker 2>/dev/null || true)"; opts="$(findmnt -no OPTIONS /var/lib/docker 2>/dev/null || true)"
  [[ "$fs" == "xfs" && "$opts" == *prjquota* ]] && lines+=("Docker storage verified: XFS with prjquota") || lines+=("Docker storage warning: expected XFS with prjquota")
else
  lines+=("Docker storage warning: /var/lib/docker is not a separate mount")
fi
command -v rig-monitor >/dev/null 2>&1 && lines+=("rig-monitor command installed") || lines+=("rig-monitor command missing")
command -v gpu_burn >/dev/null 2>&1 && lines+=("gpu_burn command installed") || lines+=("gpu_burn command missing")
command -v cpu_burn >/dev/null 2>&1 && lines+=("cpu_burn command installed") || lines+=("cpu_burn command missing")
command -v memtester >/dev/null 2>&1 && lines+=("memtester command installed") || lines+=("memtester command missing")
command -v full_burn >/dev/null 2>&1 && lines+=("full_burn command installed") || lines+=("full_burn command missing")
lines+=("Helper commands installed: storage_layout, sudo vast_ready_check, sudo disk_health, sudo docker system df, sudo vast_cleanup")

quick=("vast_install_summary" "storage_layout" "sudo vast_ready_check" "sudo disk_health" "sudo docker system df")
command -v cpu_burn >/dev/null 2>&1 && quick+=("cpu_burn 60")
command -v memtester >/dev/null 2>&1 && quick+=("memtester 60")
command -v gpu_burn >/dev/null 2>&1 && quick+=("gpu_burn -tc -m 100% 60")
if command -v full_burn >/dev/null 2>&1; then
  quick+=("full_burn 7200" "Full burn tests the whole machine: RAM + CPU + GPU together")
fi
command -v rig-monitor >/dev/null 2>&1 && quick+=("rig-monitor")

hero_banner
success_banner "PHASE 3 COMPLETE - VAST SETUP FINISHED"
install_report_box "What was done - full install report" "${lines[@]}"
install_report_box "Quick stress-test commands" "${quick[@]}"
echo "Optional next steps: connect the Vast CLI and test this machine."
command_list_box \
  "vastai --help" \
  "vastai set api-key YOUR_API_KEY" \
  "vastai show user" \
  "vastai show machines" \
  "vastai self-test machine YOUR_MACHINE_ID" \
  "vastai self-test machine YOUR_MACHINE_ID --ignore-requirements"
echo "More CLI examples: https://docs.vast.ai/cli/hello-world"
SCRIPT
chmod 0755 /usr/local/bin/vast_install_summary

for cmd in storage_layout disk_health vast_ready_check vast_cleanup vast_install_summary; do
  bash -n "/usr/local/bin/$cmd"
done
if [[ "$WITH_BURN_TOOLS" -eq 1 ]]; then
  bash -n /usr/local/bin/cpu_burn /usr/local/bin/memtester
  [[ -x /usr/local/bin/full_burn ]] && bash -n /usr/local/bin/full_burn || true
fi

cat >/var/lib/vast-host-installer/host-tools-installed.txt <<EOF
installed_at=$(date -Is)
with_burn_tools=$WITH_BURN_TOOLS
commands=vast_install_summary storage_layout vast_ready_check disk_health vast_cleanup
EOF

echo "Installed Vast host tools. Run: vast_install_summary"
