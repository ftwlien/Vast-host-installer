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
  if storage_already_correct; then
    log "storage layout already matches the intended plan; skipping storage changes"
  else
    case "$PROFILE" in
      fresh-basic|fresh-single-disk)
        ensure_single_disk_storage_layout
        ;;
      fresh-two-disk)
        ensure_two_disk_storage_layout
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
    extras_done_lines+=("CPU burn: cpu_burn 60")
  fi
  if command -v full_burn >/dev/null 2>&1; then
    extras_done_lines+=("Full burn: full_burn 7200")
  fi

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
  phase3_done_lines+=("Aggressive Vast.ai GPU fan control installed and enabled")
fi
if [[ "$WITH_GPU_BURN" -eq 1 ]]; then
  phase3_done_lines+=("gpu-burn stress-test tool installed with /usr/local/bin/gpu_burn wrapper")
fi
if [[ "$WITH_CPU_BURN" -eq 1 ]]; then
  phase3_done_lines+=("CPU burn stress-test tool installed with /usr/local/bin/cpu_burn wrapper")
fi
if command -v full_burn >/dev/null 2>&1; then
  phase3_done_lines+=("Full CPU+GPU burn command installed with /usr/local/bin/full_burn wrapper")
fi

hero_banner
success_banner "PHASE 3 COMPLETE - VAST SETUP FINISHED"
install_report_box "What was done - full install report" "${phase3_done_lines[@]}"
stress_test_lines=()
if [[ "$WITH_CPU_BURN" -eq 1 ]]; then
  stress_test_lines+=("cpu_burn 60")
fi
if [[ "$WITH_GPU_BURN" -eq 1 ]]; then
  stress_test_lines+=("gpu_burn -tc -m 100% 60")
fi
if command -v full_burn >/dev/null 2>&1; then
  stress_test_lines+=("full_burn 7200")
fi
if [[ "$WITH_RIG_MONITOR" -eq 1 ]]; then
  stress_test_lines+=("rig-monitor")
fi
if [[ "$WITH_CPU_BURN" -eq 1 || "$WITH_GPU_BURN" -eq 1 ]]; then
  stress_test_lines+=("Tip: 60 = seconds. Use 7200 for a 2-hour burn-in.")
fi
if [[ "${#stress_test_lines[@]}" -gt 0 ]]; then
  install_report_box "Quick stress-test commands" "${stress_test_lines[@]}"
fi
if [[ "$WITH_VAST_CLI" -eq 1 ]]; then
  echo "Optional next steps: connect the Vast CLI and test this machine."
  command_list_box \
    "vastai set api-key YOUR_API_KEY" \
    "vastai show machines" \
    "vastai self-test machine YOUR_MACHINE_ID" \
    "vastai self-test machine YOUR_MACHINE_ID --ignore-requirements"
  echo "More CLI examples: https://docs.vast.ai/cli/hello-world"
fi
success "Host setup finished"
