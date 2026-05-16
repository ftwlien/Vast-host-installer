#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="/var/lib/vast-host-installer"
STATE_FILE="${STATE_DIR}/resume.env"
AUTO_RESUME_SERVICE="vast-host-installer-auto-resume.service"
PROFILE="fresh-basic"
WITH_VAST_CLI=0
WITH_RIG_MONITOR=0
WITH_FLEET_HEALTH=0
WITH_GPU_FAN_CONTROL=0
WITH_GPU_BURN=0
WITH_CPU_BURN=0
PLAN_ONLY=0
PREFLIGHT_PHASE3=0
APPLY_CHANGES=0
FIRST_BOOT_MODE=0
INSTALL_EXTRAS_MODE=0
RESUME_MODE=0
AUTO_RUN=0
CURRENT_AUTO_RUN=0
NO_AUTO_REBOOT=0
RESUME_AFTER_REBOOT=0
RESUME_AFTER_NVIDIA_REBOOT=0
OFFICIAL_UBUNTU_MODE=0
CONFIRM_DISK=""
VAST_API_KEY="${VAST_API_KEY:-}"
VAST_INSTALL_COMMAND="${VAST_INSTALL_COMMAND:-}"
VAST_PORT_RANGE="${VAST_PORT_RANGE:-}"
TARGET_USER="${TARGET_USER:-}"

source "$ROOT_DIR/install/lib/common.sh"
source "$ROOT_DIR/install/lib/detect.sh"
source "$ROOT_DIR/install/lib/storage.sh"
source "$ROOT_DIR/install/lib/plan.sh"
source "$ROOT_DIR/install/lib/first_boot_questions.sh"
source "$ROOT_DIR/install/lib/profile_infer.sh"
source "$ROOT_DIR/install/lib/autoinstall_policy.sh"
source "$ROOT_DIR/install/lib/system_prep.sh"
source "$ROOT_DIR/install/lib/users.sh"
source "$ROOT_DIR/install/lib/nvidia.sh"
source "$ROOT_DIR/install/lib/docker.sh"
source "$ROOT_DIR/install/lib/vast.sh"
source "$ROOT_DIR/install/lib/extras.sh"
source "$ROOT_DIR/install/lib/verify.sh"
source "$ROOT_DIR/install/profiles/fresh-basic.sh"
source "$ROOT_DIR/install/profiles/fresh-single-disk.sh"
source "$ROOT_DIR/install/profiles/fresh-two-disk.sh"

usage() {
  cat <<EOF
Usage: bash install/main.sh [options]

Options:
  --profile <name>
  --with-vast-cli
  --with-rig-monitor
  --with-fleet-health
  --with-gpu-fan-control
  --with-gpu-burn
  --with-cpu-burn
  --vast-api-key <key>
  --vast-install-command <cmd>
  --confirm-disk <device>
  --detect-only
  --plan-only
  --preflight-phase3
  --first-run
  --install-extras
  --resume
  --auto-run
  --no-auto-reboot
  --resume-after-reboot
  --resume-after-nvidia-reboot
  --official-ubuntu
  --apply
EOF
}

DETECT_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:-}"
      shift 2
      ;;
    --with-vast-cli)
      WITH_VAST_CLI=1
      shift
      ;;
    --with-rig-monitor)
      WITH_RIG_MONITOR=1
      shift
      ;;
    --with-fleet-health)
      WITH_FLEET_HEALTH=1
      shift
      ;;
    --with-gpu-fan-control)
      WITH_GPU_FAN_CONTROL=1
      shift
      ;;
    --with-gpu-burn)
      WITH_GPU_BURN=1
      shift
      ;;
    --with-cpu-burn)
      WITH_CPU_BURN=1
      shift
      ;;
    --vast-api-key)
      VAST_API_KEY="${2:-}"
      shift 2
      ;;
    --vast-install-command)
      VAST_INSTALL_COMMAND="${2:-}"
      shift 2
      ;;
    --confirm-disk)
      CONFIRM_DISK="${2:-}"
      shift 2
      ;;
    --detect-only)
      DETECT_ONLY=1
      shift
      ;;
    --plan-only)
      PLAN_ONLY=1
      shift
      ;;
    --preflight-phase3)
      PREFLIGHT_PHASE3=1
      shift
      ;;
    --first-run)
      FIRST_BOOT_MODE=1
      shift
      ;;
    --install-extras)
      INSTALL_EXTRAS_MODE=1
      APPLY_CHANGES=1
      shift
      ;;
    --resume)
      RESUME_MODE=1
      shift
      ;;
    --auto-run)
      AUTO_RUN=1
      CURRENT_AUTO_RUN=1
      shift
      ;;
    --no-auto-reboot)
      NO_AUTO_REBOOT=1
      shift
      ;;
    --resume-after-reboot)
      RESUME_AFTER_REBOOT=1
      shift
      ;;
    --resume-after-nvidia-reboot)
      RESUME_AFTER_NVIDIA_REBOOT=1
      shift
      ;;
    --official-ubuntu|--post-ubuntu)
      OFFICIAL_UBUNTU_MODE=1
      shift
      ;;
    --apply)
      APPLY_CHANGES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

save_resume_state() {
  local next_phase="$1"
  mkdir -p "$STATE_DIR"
  {
    printf 'PROFILE=%q\n' "$PROFILE"
    printf 'ROOT_DIR=%q\n' "$ROOT_DIR"
    printf 'VAST_INSTALL_COMMAND=%q\n' "$VAST_INSTALL_COMMAND"
    printf 'VAST_PORT_RANGE=%q\n' "$VAST_PORT_RANGE"
    printf 'TARGET_USER=%q\n' "$TARGET_USER"
    printf 'WITH_VAST_CLI=%q\n' "$WITH_VAST_CLI"
    printf 'WITH_RIG_MONITOR=%q\n' "$WITH_RIG_MONITOR"
    printf 'WITH_FLEET_HEALTH=%q\n' "$WITH_FLEET_HEALTH"
    printf 'WITH_GPU_FAN_CONTROL=%q\n' "$WITH_GPU_FAN_CONTROL"
    printf 'WITH_GPU_BURN=%q\n' "$WITH_GPU_BURN"
    printf 'WITH_CPU_BURN=%q\n' "$WITH_CPU_BURN"
    printf 'OFFICIAL_UBUNTU_MODE=%q\n' "$OFFICIAL_UBUNTU_MODE"
    printf 'AUTO_RUN=%q\n' "$AUTO_RUN"
    printf 'NEXT_PHASE=%q\n' "$next_phase"
  } > "$STATE_FILE"
  chmod 0600 "$STATE_FILE"
}

load_resume_state() {
  [[ -f "$STATE_FILE" ]] || die "No saved resume state found. Run --first-run first."
  # shellcheck disable=SC1090
  source "$STATE_FILE"
  PROFILE="${PROFILE:-fresh-basic}"
  ROOT_DIR="${ROOT_DIR:-$ROOT_DIR}"
  VAST_INSTALL_COMMAND="${VAST_INSTALL_COMMAND:-}"
  VAST_PORT_RANGE="${VAST_PORT_RANGE:-}"
  TARGET_USER="${TARGET_USER:-}"
  WITH_VAST_CLI="${WITH_VAST_CLI:-0}"
  WITH_RIG_MONITOR="${WITH_RIG_MONITOR:-0}"
  WITH_FLEET_HEALTH="${WITH_FLEET_HEALTH:-0}"
  WITH_GPU_FAN_CONTROL="${WITH_GPU_FAN_CONTROL:-0}"
  WITH_GPU_BURN="${WITH_GPU_BURN:-0}"
  WITH_CPU_BURN="${WITH_CPU_BURN:-0}"
  OFFICIAL_UBUNTU_MODE="${OFFICIAL_UBUNTU_MODE:-0}"
  AUTO_RUN="${AUTO_RUN:-0}"
  case "${NEXT_PHASE:-}" in
    after-reboot)
      RESUME_AFTER_REBOOT=1
      APPLY_CHANGES=1
      ;;
    after-nvidia-reboot)
      RESUME_AFTER_NVIDIA_REBOOT=1
      APPLY_CHANGES=1
      ;;
    *)
      die "Saved resume state is invalid or missing NEXT_PHASE."
      ;;
  esac
}

enable_auto_resume() {
  sudo systemctl daemon-reload || true
  if systemctl list-unit-files "$AUTO_RESUME_SERVICE" >/dev/null 2>&1; then
    sudo systemctl enable "$AUTO_RESUME_SERVICE" >/dev/null
  fi
}

disable_auto_resume() {
  if systemctl list-unit-files "$AUTO_RESUME_SERVICE" >/dev/null 2>&1; then
    sudo systemctl disable "$AUTO_RESUME_SERVICE" >/dev/null 2>&1 || true
  fi
}

continue_after_phase() {
  local next_step="$1"
  if [[ "$AUTO_RUN" -eq 1 && "$NO_AUTO_REBOOT" -ne 1 ]]; then
    disable_auto_resume
    echo "$next_step"
    echo "Rebooting now. After boot, log in and run --resume so you can watch the next phase."
    sudo reboot
    exit 0
  fi
  echo "$next_step"
  command_box "sudo /opt/vast-host-installer/bin/vast-host-installer --resume"
  prompt_reboot_now
}

continue_to_manual_phase3() {
  local next_step="$1"
  disable_auto_resume
  echo "$next_step"
  echo "Phase 3 is interactive because the Vast installer asks for ports."
  echo "Auto-resume is disabled now so systemd will not run the Vast installer without your terminal."
  command_box "sudo /opt/vast-host-installer/bin/vast-host-installer --preflight-phase3"
  if [[ "$AUTO_RUN" -eq 1 && "$NO_AUTO_REBOOT" -ne 1 ]]; then
    echo "Auto mode: rebooting now. Log in after boot and run the preflight command above."
    sudo reboot
    exit 0
  fi
  prompt_reboot_now
}

require_interactive_phase3() {
  if [[ "$CURRENT_AUTO_RUN" -eq 1 || ! -t 0 ]]; then
    disable_auto_resume
    banner "Phase 3 - Manual Vast Setup Required"
    echo "NVIDIA setup is complete."
    echo "The Vast installer is interactive and must run from your SSH/console session."
    echo "Log in and run the preflight check first:"
    command_box "sudo /opt/vast-host-installer/bin/vast-host-installer --preflight-phase3"
    exit 0
  fi
}

mark_setup_complete() {
  sudo mkdir -p "$STATE_DIR"
  printf 'completed_at=%s\nprofile=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROFILE" | sudo tee "$STATE_DIR/setup-complete" >/dev/null
  sudo rm -f "$STATE_FILE"
  disable_auto_resume
}

ensure_basic_tools

if [[ "$FIRST_BOOT_MODE" -ne 1 ]]; then
  hero_banner
fi

if [[ "$RESUME_MODE" -eq 1 ]]; then
  load_resume_state
fi

if [[ "$DETECT_ONLY" -eq 1 ]]; then
  print_detection_summary
  plan_storage_layout
  emit_autoinstall_storage_policy
  exit 0
fi

if [[ "$PLAN_ONLY" -eq 1 ]]; then
  print_detection_summary
  plan_storage_layout
  emit_autoinstall_storage_policy
  emit_plan_preview "$PROFILE"
  exit 0
fi

if [[ "$PREFLIGHT_PHASE3" -eq 1 ]]; then
  preflight_phase3
  exit 0
fi

if [[ "$FIRST_BOOT_MODE" -eq 1 ]]; then
  AUTO_RUN=1
  run_first_boot_questionnaire
  PROFILE="$(infer_profile_from_layout)"
  VAST_INSTALL_COMMAND="$FIRST_BOOT_VAST_INSTALL_COMMAND"
  TARGET_USER="$FIRST_BOOT_USERNAME"
  WITH_VAST_CLI="$FIRST_BOOT_INSTALL_VAST_CLI"
  WITH_RIG_MONITOR="$FIRST_BOOT_INSTALL_RIG_MONITOR"
  WITH_FLEET_HEALTH="$FIRST_BOOT_INSTALL_FLEET_HEALTH"
  WITH_GPU_FAN_CONTROL="$FIRST_BOOT_INSTALL_GPU_FAN_CONTROL"
  WITH_GPU_BURN="$FIRST_BOOT_INSTALL_GPU_BURN"
  WITH_CPU_BURN="$FIRST_BOOT_INSTALL_CPU_BURN"

  set_final_hostname "$FIRST_BOOT_HOSTNAME"
  ensure_operator_user "$FIRST_BOOT_USERNAME" "$FIRST_BOOT_PASSWORD"
  lock_bootstrap_user_after_handoff "$FIRST_BOOT_USERNAME"

  print_detection_summary
  plan_storage_layout
  emit_autoinstall_storage_policy
  emit_plan_preview "$PROFILE"

  banner "Phase 1 - Storage and System Prep"
  if [[ "$OFFICIAL_UBUNTU_MODE" -eq 1 ]]; then
    log "official Ubuntu mode: leaving Docker/Vast storage layout unchanged; Vast installer will handle its own setup"
  elif storage_already_correct; then
    log "storage layout already matches the intended plan; skipping storage changes"
  else
    case "$PROFILE" in
      fresh-basic|fresh-single-disk)
        ensure_single_disk_storage_layout
        ;;
      fresh-two-disk)
        ensure_two_disk_storage_layout
        ;;
      fresh-multi-disk-raid0)
        ensure_multi_disk_raid0_storage_layout
        ;;
      *)
        die "Unknown profile for first-run prep phase: $PROFILE"
        ;;
    esac
  fi
  run_base_system_prep_from_known_good_flow
  save_resume_state after-reboot

  success_banner "PHASE 1 COMPLETE - REBOOTING NEXT"
  summary_box "What was done" \
    "Final hostname was set" \
    "Operator user was created" \
    "Storage layout was prepared for this rig" \
    "Base system prep finished" \
    "Resume state was saved for phase 2"
  continue_after_phase "Next step: reboot, then log in and run --resume to start NVIDIA setup."
fi

if [[ "$INSTALL_EXTRAS_MODE" -eq 1 ]]; then
  run_optional_extras_questionnaire
  TARGET_USER="$(installer_target_user)"
  WITH_VAST_CLI="$FIRST_BOOT_INSTALL_VAST_CLI"
  WITH_RIG_MONITOR="$FIRST_BOOT_INSTALL_RIG_MONITOR"
  WITH_FLEET_HEALTH="$FIRST_BOOT_INSTALL_FLEET_HEALTH"
  WITH_GPU_FAN_CONTROL="$FIRST_BOOT_INSTALL_GPU_FAN_CONTROL"
  WITH_GPU_BURN="$FIRST_BOOT_INSTALL_GPU_BURN"
  WITH_CPU_BURN="$FIRST_BOOT_INSTALL_CPU_BURN"

  if [[ "$WITH_VAST_CLI$WITH_RIG_MONITOR$WITH_FLEET_HEALTH$WITH_GPU_FAN_CONTROL$WITH_GPU_BURN$WITH_CPU_BURN" == "000000" ]]; then
    success "No optional extras selected"
    exit 0
  fi

  banner "Installing Selected Optional Extras"
  if [[ "$WITH_VAST_CLI" -eq 1 ]]; then
    install_vast_cli
  fi
  if [[ "$WITH_RIG_MONITOR" -eq 1 ]]; then
    install_rig_monitor_placeholder
  fi
  if [[ "$WITH_FLEET_HEALTH" -eq 1 ]]; then
    install_fleet_health_placeholder
  fi
  if [[ "$WITH_GPU_FAN_CONTROL" -eq 1 ]]; then
    install_gpu_fan_control
  fi
  if [[ "$WITH_GPU_BURN" -eq 1 ]]; then
    install_gpu_burn
  fi
  if [[ "$WITH_CPU_BURN" -eq 1 ]]; then
    install_cpu_burn
  fi
  install_full_burn_if_ready
  install_host_polish_tools

  extras_done_lines=("Selected optional extras installed or repaired")
  if [[ "$WITH_VAST_CLI" -eq 1 ]]; then
    extras_done_lines+=("Vast CLI: vastai")
  fi
  if [[ "$WITH_RIG_MONITOR" -eq 1 ]]; then
    extras_done_lines+=("rig-monitor: rig-monitor")
  fi
  if [[ "$WITH_FLEET_HEALTH" -eq 1 ]]; then
    extras_done_lines+=("Fleet Health Check prerequisites installed")
  fi
  if [[ "$WITH_GPU_FAN_CONTROL" -eq 1 ]]; then
    extras_done_lines+=("GPU fan control services installed/enabled")
  fi
  if [[ "$WITH_GPU_BURN" -eq 1 ]]; then
    extras_done_lines+=("GPU burn: gpu_burn -tc -m 100% 60")
  fi
  if [[ "$WITH_CPU_BURN" -eq 1 ]]; then
    extras_done_lines+=("CPU/RAM burn: cpu_burn 60 and sudo ram_burn 60")
  fi
  if command -v full_burn >/dev/null 2>&1; then
    extras_done_lines+=("Full burn: full_burn 7200 logs to ~/burn-logs")
  fi
  extras_done_lines+=("Readiness tools: storage_layout, sudo vast_ready_check, sudo disk_health, sudo vast_system_update, sudo vast_cleanup, sudo rig-burn-cleanup")

  success_banner "OPTIONAL EXTRAS COMPLETE"
  install_report_box "What was installed" "${extras_done_lines[@]}"
  success "Optional extras finished"
  exit 0
fi

if [[ "$RESUME_AFTER_REBOOT" -eq 1 ]]; then
  [[ "$APPLY_CHANGES" -eq 1 ]] || die "--resume-after-reboot requires --apply"
  banner "Phase 2 - NVIDIA Open Driver Setup"
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    log "NVIDIA is already working; skipping Phase 2 driver install"
  else
    install_nvidia_590_open_from_known_good_flow
  fi
  save_resume_state after-nvidia-reboot
  success_banner "PHASE 2 COMPLETE - NVIDIA READY"
  summary_box "What was done" \
    "Recommended NVIDIA driver was installed" \
    "GPU driver readiness was checked" \
    "Resume state was saved for the final interactive Vast phase"
  continue_to_manual_phase3 "Next step: reboot, then run Phase 3 manually from SSH/console."
fi

if [[ "$RESUME_AFTER_NVIDIA_REBOOT" -eq 1 ]]; then
  [[ "$APPLY_CHANGES" -eq 1 ]] || die "--resume-after-nvidia-reboot requires --apply"
  require_interactive_phase3
fi

if [[ "$RESUME_AFTER_NVIDIA_REBOOT" -eq 1 && -t 0 ]]; then
  install_vast_machine_id_tool
  install_vast_power_limit_tool
  banner "Optional Persistent GPU Power Limit"
  echo "This is NOT enabled by default. Set it only if you want a reboot-persistent NVIDIA power cap."
  echo "It keeps NVIDIA persistence mode ON (-pm 1), which is the safer Vast host behavior."
  echo
  read -r -p "Power limit watts for all GPUs (blank to skip): " VAST_POWER_LIMIT_WATTS
  if [[ -n "${VAST_POWER_LIMIT_WATTS:-}" ]]; then
    case "$VAST_POWER_LIMIT_WATTS" in
      *[!0-9]*) die "Power limit must be a whole number of watts, or blank to skip." ;;
      *) sudo vast_power_limit "$VAST_POWER_LIMIT_WATTS" ;;
    esac
  else
    log "persistent GPU power limit skipped by operator choice"
  fi
fi

if [[ "$APPLY_CHANGES" -ne 1 ]]; then
  die "Refusing to apply changes without --apply. Use --plan-only first to inspect the plan."
fi

case "$PROFILE" in
  fresh-basic)
    run_profile_fresh_basic
    ;;
  fresh-single-disk)
    run_profile_fresh_single_disk
    ;;
  fresh-two-disk)
    run_profile_fresh_two_disk
    ;;
  fresh-multi-disk-raid0)
    run_profile_fresh_basic
    ;;
  reinstall-same-id|reinstall-clean)
    die "Profile $PROFILE is planned but not implemented yet"
    ;;
  *)
    die "Unknown profile: $PROFILE"
    ;;
esac

if [[ "$WITH_VAST_CLI" -eq 1 ]]; then
  install_vast_cli
fi
if [[ "$WITH_RIG_MONITOR" -eq 1 ]]; then
  install_rig_monitor_placeholder
fi
if [[ "$WITH_FLEET_HEALTH" -eq 1 ]]; then
  install_fleet_health_placeholder
fi
if [[ "$WITH_GPU_FAN_CONTROL" -eq 1 ]]; then
  install_gpu_fan_control
fi
if [[ "$WITH_GPU_BURN" -eq 1 ]]; then
  install_gpu_burn
fi
if [[ "$WITH_CPU_BURN" -eq 1 ]]; then
  install_cpu_burn
fi
install_full_burn_if_ready
install_host_polish_tools

verify_host_state
mark_setup_complete

phase3_done_lines=(
  "Profile applied: $PROFILE"
  "Ubuntu apt update, upgrade and dist-upgrade completed during base prep"
  "Kernel/update tooling installed: update-manager-core, build-essential and linux headers"
  "Unattended upgrades removed: sudo apt purge --auto-remove unattended-upgrades -y"
  "apt-daily-upgrade.timer disabled and apt-daily-upgrade.service masked"
  "apt-daily.timer disabled and apt-daily.service masked"
  "NVIDIA driver refreshed using Ubuntu's recommended open driver package"
  "Old NVIDIA packages purged before installing the selected driver"
  "CUDA/NVIDIA userspace path prepared through the NVIDIA/Vast runtime flow"
  "nvidia-xconfig enabled: Coolbits=28, empty initial config, all GPUs"
  "Persistence mode enabled at boot: @reboot nvidia-smi -pm 1"
  "Vast host installer completed and Vast core services were verified"
  "Docker NVIDIA runtime verified for Vast containers"
  "vast_metrics launcher chmod repaired and vast_metrics restarted when present"
  "Final host verification completed"
)
if [[ "$WITH_VAST_CLI" -eq 1 ]]; then
  phase3_done_lines+=("Vast CLI installed and /usr/local/bin/vastai wrapper created")
fi
if [[ "$WITH_RIG_MONITOR" -eq 1 ]]; then
  phase3_done_lines+=("rig-monitor installed with /usr/local/bin/rig-monitor launcher")
fi
if [[ "$WITH_FLEET_HEALTH" -eq 1 ]]; then
  phase3_done_lines+=("Fleet Health Check prerequisites installed")
fi
if [[ "$WITH_GPU_FAN_CONTROL" -eq 1 ]]; then
  phase3_done_lines+=("GPU fan control installed with switchable global/per-GPU modes")
fi
burn_cmds=()
if [[ "$WITH_CPU_BURN" -eq 1 ]]; then
  burn_cmds+=("cpu_burn" "ram_burn")
fi
if [[ "$WITH_GPU_BURN" -eq 1 ]]; then
  burn_cmds+=("gpu_burn")
fi
if command -v full_burn >/dev/null 2>&1; then
  burn_cmds+=("full_burn")
fi
if (( ${#burn_cmds[@]} > 0 )); then
  joined="${burn_cmds[*]}"
  phase3_done_lines+=("Stress-test commands installed: ${joined// /, }")
fi
phase3_done_lines+=("Host polish commands installed")
phase3_done_lines+=("Setup summary command installed: vastsetup")

host_polish_lines=(
  "storage_layout - Show disk layout and Docker storage"
  "sudo vast_ready_check - Full Vast host readiness check"
  "sudo disk_health - Disk health and filesystem check"
  "sudo docker system df - Docker disk usage"
  "sudo vast_system_update - Manual updates when idle"
  "sudo vast_cleanup - Clean idle/unlisted host leftovers"
  "sudo vast_port_check - Verify Vast host ports"
  "sudo vast_machine_id show - Show/save Vast machine ID before reinstall"
  "sudo vast_machine_id restore <id> - Restore ID before Vast install/register"
  "sudo vast_backup_identity - Print machine ID + port range backup"
  "sudo vast_doctor - One-shot health check for Vast host"
  "sudo vast_power_limit <watts> - Optional persistent GPU power limit"
  "sudo vast_power_limit status - Show current/default/max power limits"
  "sudo vast_power_limit disable - Remove persistent GPU power limit"
  "sudo vast_api_key_cleanup - Remove stored Vast CLI/API key config"
  "sudo rig-burn-cleanup - Kill stuck burn-test leftovers"
)
if command -v vast_gpu_fan_mode >/dev/null 2>&1; then
  host_polish_lines+=("sudo vast_gpu_fan_mode status - Check GPU fan mode/status")
  host_polish_lines+=("sudo vast_gpu_fan_mode per-gpu - Smart per-GPU fan mode")
  host_polish_lines+=("sudo vast_gpu_fan_mode global - Global max-temp fan mode")
fi

post_cleanup_cmd="/usr/local/bin/vast_post_install_cleanup"
sudo tee "$post_cleanup_cmd" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

assume_yes=0
remove_installer=0

usage() {
  cat <<'EOF'
Usage: sudo vast_post_install_cleanup [--yes] [--remove-installer]

Removes post-install ISO/bootstrap leftovers after the final sudo user works
and the Vast host has been verified.

Options:
  --yes               Do not prompt before cleanup
  --remove-installer  Also remove /opt/vast-host-installer and source helper
EOF
}

for arg in "$@"; do
  case "$arg" in
    -y|--yes) assume_yes=1 ;;
    --remove-installer) remove_installer=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

confirm() {
  local prompt="$1" answer
  if [[ "$assume_yes" -eq 1 ]]; then
    return 0
  fi
  read -r -p "$prompt [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$|^[Yy][Ee][Ss]$ ]]
}

echo "Post-install security cleanup"
echo "Run this only after your final sudo user works and Vast is verified."
if ! confirm "Continue"; then
  echo "Cancelled."
  exit 0
fi

if getent passwd vastbootstrap >/dev/null 2>&1; then
  deluser --remove-home vastbootstrap || true
fi
if getent passwd ubuntu >/dev/null 2>&1; then
  deluser --remove-home ubuntu || true
fi

rm -f /var/lib/vast-host-installer/resume.env /tmp/vast-install.sh
rm -rf /tmp/vast-install.*
rm -f /var/log/installer/autoinstall-user-data /var/log/installer/user-data \
  /var/lib/cloud/seed/nocloud*/user-data \
  /var/lib/cloud/instance/user-data.txt \
  /var/lib/cloud/instances/*/user-data.txt \
  /autoinstall.yaml
rm -f /var/log/cloud-init.log /var/log/cloud-init-output.log
rm -rf /var/log/installer/subiquity* /var/log/installer/curtin*

if [[ -f /etc/sudoers.d/rig-monitor-launcher ]]; then
  sed -i '/^vastbootstrap[[:space:]]/d' /etc/sudoers.d/rig-monitor-launcher || true
fi
visudo -c

systemctl disable --now vast-host-installer-first-run-notice.service vast-host-installer-auto-resume.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/vast-host-installer-first-run-notice.service \
  /etc/systemd/system/vast-host-installer-auto-resume.service \
  /etc/profile.d/vast-host-installer.sh
systemctl daemon-reload

rm -f /etc/apt/apt.conf.d/90vast-host-installer-noninteractive \
  /etc/needrestart/conf.d/90-vast-host-installer.conf

if [[ "$remove_installer" -eq 1 ]]; then
  rm -rf /opt/vast-host-installer /usr/local/bin/vast-host-installer-source
fi

# Keep the Post-install security cleanup section in vastsetup.
# It includes long-term helpers such as vast_api_key_cleanup that may be useful later.

echo
echo "Cleanup complete. Current sudo group:"
getent group sudo || true

if command -v vastsetup >/dev/null 2>&1; then
  echo
  echo "Reopening clean install summary..."
  exec vastsetup
fi
SCRIPT
sudo chmod 0755 "$post_cleanup_cmd"
sudo bash -n "$post_cleanup_cmd"

machine_id_masked="missing/new identity"
if machine_id_raw="$(cat /var/lib/vastai_kaalia/machine_id 2>/dev/null)" && [[ -n "$machine_id_raw" ]]; then
  if [[ ${#machine_id_raw} -gt 14 ]]; then
    machine_id_masked="${machine_id_raw:0:6}...${machine_id_raw: -5}"
  else
    machine_id_masked="$machine_id_raw"
  fi
fi
machine_identity_lines=(
  "Machine ID: $machine_id_masked"
  "Show/save before reinstall: sudo vast_machine_id show"
  "Restore before Vast install/register: sudo vast_machine_id restore <id>"
  "Backup identity + ports: sudo vast_backup_identity"
)

pm_values="$(nvidia-smi --query-gpu=persistence_mode --format=csv,noheader 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//' || true)"
if echo "$pm_values" | grep -qi 'Disabled'; then
  pm_status="not fully enabled ($pm_values)"
elif [[ -n "$pm_values" ]]; then
  pm_status="enabled/running ($pm_values)"
else
  pm_status="unknown"
fi
power_limit_lines=(
  "NVIDIA persistence mode: $pm_status"
  "Persistent power-limit service: $(systemctl is-enabled vast-nvidia-power-limit.service 2>/dev/null || echo disabled/not configured)"
  "Show current/default/max: sudo vast_power_limit status"
  "Set only by operator choice: sudo vast_power_limit <watts>"
  "Disable: sudo vast_power_limit disable"
)
if [[ -f /etc/default/vast-nvidia-power-limit ]]; then
  power_limit_lines+=("Configured: $(cat /etc/default/vast-nvidia-power-limit)")
else
  power_limit_lines+=("Configured: not set — this is intentional unless operator chose a watt limit")
fi

bootstrap_cleanup_lines=(
  "Run only after your final sudo user works and Vast is verified"
  "sudo vast_post_install_cleanup - Remove ISO/bootstrap leftovers"
  "sudo vast_api_key_cleanup - Remove stored Vast CLI/API key config"
  "Optional: sudo vast_post_install_cleanup --remove-installer"
  "Verify sudo users after cleanup: getent group sudo"
)

stress_test_lines=()
if [[ "$WITH_CPU_BURN" -eq 1 ]]; then
  stress_test_lines+=("cpu_burn 60")
  stress_test_lines+=("sudo ram_burn 60")
fi
if [[ "$WITH_GPU_BURN" -eq 1 ]]; then
  stress_test_lines+=("gpu_burn -tc -m 100% 60")
fi
if command -v full_burn >/dev/null 2>&1; then
  stress_test_lines+=("full_burn 7200 - Full burn: RAM + CPU + GPU together")
fi
if [[ "$WITH_CPU_BURN" -eq 1 || "$WITH_GPU_BURN" -eq 1 ]]; then
  stress_test_lines+=("Tip: 60 = seconds. Use 7200 for a 2-hour burn-in.")
fi

summary_file="${STATE_DIR}/final-summary.txt"
summary_cmd="/usr/local/bin/vast_install_summary"
summary_tmp="$(mktemp)"
{
  echo "VAST HOST - PHASE 3 COMPLETE - VAST SETUP FINISHED"
  echo "Generated: $(date -Is)"
  echo
  echo "What was done - full install report"
  for line in "${phase3_done_lines[@]}"; do
    echo "✓ $line"
  done
  echo
  echo "Vast.ai host port range"
  echo "✓ Current: $(cat /var/lib/vastai_kaalia/host_port_range 2>/dev/null || echo missing)"
  echo "✓ Show current: cat /var/lib/vastai_kaalia/host_port_range"
  echo "✓ Change only if needed: sudo vast_port_range START-END"
  echo "✓ Check: sudo vast_port_check"
  echo
  echo "Vast machine identity"
  for line in "${machine_identity_lines[@]}"; do
    echo "✓ $line"
  done
  echo
  echo "GPU power limit"
  for line in "${power_limit_lines[@]}"; do
    echo "✓ $line"
  done
  echo
  echo "Quick stress-test commands"
  for line in "${stress_test_lines[@]}"; do
    echo "✓ $line"
  done
  echo
  echo "Useful host polish commands"
  for line in "${host_polish_lines[@]}"; do
    echo "✓ $line"
  done
  echo
  echo "Post-install security cleanup"
  for line in "${bootstrap_cleanup_lines[@]}"; do
    echo "✓ $line"
  done
  echo
  echo "Setup summary"
  echo "✓ vastsetup - Show this screen again"
  echo "✓ vast_install_summary - Same command, old name"
  echo "✓ vastsetup --plain - Plain CLI-style summary"
  if [[ "$WITH_VAST_CLI" -eq 1 ]]; then
    echo
    echo "Optional next steps - Vast CLI"
    echo "vastai --help"
    echo "vastai set api-key YOUR_API_KEY"
    echo "vastai show user"
    echo "vastai show machines"
    echo "vastai self-test machine YOUR_MACHINE_ID"
    echo "vastai self-test machine YOUR_MACHINE_ID --ignore-requirements"
    echo "More CLI examples: https://docs.vast.ai/cli/hello-world"
  fi
} > "$summary_tmp"
sudo install -d -m 0755 "$STATE_DIR"
sudo install -m 0644 "$summary_tmp" "$summary_file"
rm -f "$summary_tmp"
sudo tee "$summary_cmd" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
summary_file="/var/lib/vast-host-installer/final-summary.txt"
if [[ ! -r "$summary_file" ]]; then
  echo "No final Vast Host install summary found at $summary_file" >&2
  echo "Finish Phase 3 first, then run vastsetup again." >&2
  exit 1
fi

if [[ "${1:-}" == "--plain" || "${1:-}" == "plain" ]]; then
  cat "$summary_file"
  exit 0
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
          printf '%b│%b %s%b%-*s %b│%b\n' "$C_SKY$C_BOLD" "$C_GREEN" "$prefix" "$C_WHITE$C_BOLD" "$available" "$wrapped" "$C_SKY$C_BOLD" "$C_RESET"
          break
        fi
        chunk="${wrapped:0:$available}"
        if [[ "$chunk" == *" "* ]]; then
          chunk="${chunk% *}"
          [[ -n "$chunk" ]] || chunk="${wrapped:0:$available}"
        fi
        printf '%b│%b %s%b%-*s %b│%b\n' "$C_SKY$C_BOLD" "$C_GREEN" "$prefix" "$C_WHITE$C_BOLD" "$available" "$chunk" "$C_SKY$C_BOLD" "$C_RESET"
        wrapped="${wrapped:${#chunk}}"
        wrapped="${wrapped# }"
        prefix="  "
      done
    done
  fi
  printf '%b╰%s╯%b\n' "$C_SKY$C_BOLD" "$(_box_line '─' "$width")" "$C_RESET"
}

done_lines=(); port_lines=(); identity_lines=(); power_lines=(); quick_lines=(); polish_lines=(); cleanup_lines=(); setup_lines=(); cli_lines=(); section=""
while IFS= read -r line; do
  case "$line" in
    "What was done - full install report") section="done"; continue ;;
    "Vast.ai host port range") section="port"; continue ;;
    "Vast machine identity") section="identity"; continue ;;
    "GPU power limit") section="power"; continue ;;
    "Quick stress-test commands") section="quick"; continue ;;
    "Useful host polish commands") section="polish"; continue ;;
    "Post-install security cleanup") section="cleanup"; continue ;;
    "Setup summary") section="setup"; continue ;;
    "Optional next steps - Vast CLI") section="cli"; continue ;;
    "VAST HOST - "*|"Generated: "*|"") continue ;;
  esac
  line="${line#✓ }"
  if [[ "$section" == "port" && "$line" == Current:* ]]; then
    line="Current: $(cat /var/lib/vastai_kaalia/host_port_range 2>/dev/null || echo missing)"
  fi
  case "$section" in
    done) done_lines+=("$line") ;;
    port) port_lines+=("$line") ;;
    identity) identity_lines+=("$line") ;;
    power) power_lines+=("$line") ;;
    quick) quick_lines+=("$line") ;;
    polish) polish_lines+=("$line") ;;
    cleanup) cleanup_lines+=("$line") ;;
    setup) setup_lines+=("$line") ;;
    cli) cli_lines+=("$line") ;;
  esac
done < "$summary_file"

hero_banner
success_banner "PHASE 3 COMPLETE - VAST SETUP FINISHED"
install_report_box "What was done - full install report" "${done_lines[@]}"
if [[ "${#port_lines[@]}" -gt 0 ]]; then
  install_report_box "Vast.ai host port range" "${port_lines[@]}"
fi
if [[ "${#identity_lines[@]}" -gt 0 ]]; then
  install_report_box "Vast machine identity" "${identity_lines[@]}"
fi
if [[ "${#power_lines[@]}" -gt 0 ]]; then
  install_report_box "GPU power limit" "${power_lines[@]}"
fi
if [[ "${#quick_lines[@]}" -gt 0 ]]; then
  install_report_box "Quick stress-test commands" "${quick_lines[@]}"
fi
if [[ "${#polish_lines[@]}" -gt 0 ]]; then
  install_report_box "Useful host polish commands" "${polish_lines[@]}"
fi
if [[ "${#cleanup_lines[@]}" -gt 0 ]]; then
  install_report_box "Post-install security cleanup" "${cleanup_lines[@]}"
fi
if [[ "${#setup_lines[@]}" -gt 0 ]]; then
  install_report_box "Setup summary" "${setup_lines[@]}"
fi
if [[ "${#cli_lines[@]}" -gt 0 ]]; then
  install_report_box "Optional next steps - Vast CLI" "${cli_lines[@]}"
fi
EOF
sudo chmod 0755 "$summary_cmd"
sudo ln -sf vast_install_summary /usr/local/bin/vastsetup
sudo bash -n "$summary_cmd"

hero_banner
success_banner "PHASE 3 COMPLETE - VAST SETUP FINISHED"
install_report_box "What was done - full install report" "${phase3_done_lines[@]}"
port_lines=("Current: $(cat /var/lib/vastai_kaalia/host_port_range 2>/dev/null || echo missing)" "Show current: cat /var/lib/vastai_kaalia/host_port_range" "Change only if needed: sudo vast_port_range START-END" "Check: sudo vast_port_check")
install_report_box "Vast.ai host port range" "${port_lines[@]}"
install_report_box "Vast machine identity" "${machine_identity_lines[@]}"
install_report_box "GPU power limit" "${power_limit_lines[@]}"
if [[ "${#stress_test_lines[@]}" -gt 0 ]]; then
  install_report_box "Quick stress-test commands" "${stress_test_lines[@]}"
fi
install_report_box "Useful host polish commands" "${host_polish_lines[@]}"
install_report_box "Post-install security cleanup" "${bootstrap_cleanup_lines[@]}"
install_report_box "Setup summary" "vastsetup - Show this screen again" "vast_install_summary - Same command, old name" "vastsetup --plain - Plain CLI-style summary"
if [[ "$WITH_VAST_CLI" -eq 1 ]]; then
  echo "Optional next steps: connect the Vast CLI and test this machine."
  command_list_box \
    "vastai --help" \
    "vastai set api-key YOUR_API_KEY" \
    "vastai show user" \
    "vastai show machines" \
    "vastai self-test machine YOUR_MACHINE_ID" \
    "vastai self-test machine YOUR_MACHINE_ID --ignore-requirements"
  echo "More CLI examples: https://docs.vast.ai/cli/hello-world"
fi
success "Host setup finished"
