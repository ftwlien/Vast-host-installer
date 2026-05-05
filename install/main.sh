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
PLAN_ONLY=0
APPLY_CHANGES=0
FIRST_BOOT_MODE=0
RESUME_MODE=0
AUTO_RUN=0
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
  --vast-api-key <key>
  --vast-install-command <cmd>
  --confirm-disk <device>
  --detect-only
  --plan-only
  --first-run
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
    --first-run)
      FIRST_BOOT_MODE=1
      shift
      ;;
    --resume)
      RESUME_MODE=1
      shift
      ;;
    --auto-run)
      AUTO_RUN=1
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
    enable_auto_resume
    echo "$next_step"
    echo "Auto mode: rebooting now. Setup will continue automatically after boot."
    sudo reboot
    exit 0
  fi
  echo "$next_step"
  command_box "sudo /opt/vast-host-installer/bin/vast-host-installer --resume"
  prompt_reboot_now
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

if [[ "$FIRST_BOOT_MODE" -eq 1 ]]; then
  AUTO_RUN=1
  run_first_boot_questionnaire
  PROFILE="$(infer_profile_from_layout)"
  VAST_INSTALL_COMMAND="$FIRST_BOOT_VAST_INSTALL_COMMAND"
  TARGET_USER="$FIRST_BOOT_USERNAME"
  WITH_VAST_CLI="$FIRST_BOOT_INSTALL_VAST_CLI"
  WITH_RIG_MONITOR="$FIRST_BOOT_INSTALL_RIG_MONITOR"
  WITH_FLEET_HEALTH="$FIRST_BOOT_INSTALL_FLEET_HEALTH"

  set_final_hostname "$FIRST_BOOT_HOSTNAME"
  ensure_operator_user "$FIRST_BOOT_USERNAME" "$FIRST_BOOT_PASSWORD"

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

  banner "Phase 1 Complete"
  summary_box "What was done" \
    "Final hostname was set" \
    "Operator user was created" \
    "Storage layout was prepared for this rig" \
    "Base system prep finished" \
    "Resume state was saved for phase 2"
  continue_after_phase "Next step: reboot, then NVIDIA setup will continue."
fi

if [[ "$RESUME_AFTER_REBOOT" -eq 1 ]]; then
  [[ "$APPLY_CHANGES" -eq 1 ]] || die "--resume-after-reboot requires --apply"
  banner "Phase 2 - NVIDIA Open Driver Setup"
  install_nvidia_590_open_from_known_good_flow
  save_resume_state after-nvidia-reboot
  banner "Phase 2 Complete"
  summary_box "What was done" \
    "Recommended NVIDIA driver was installed" \
    "GPU driver readiness was checked" \
    "Resume state was saved for the final Vast phase"
  continue_after_phase "Next step: reboot, then Vast setup will continue."
fi

if [[ "$RESUME_AFTER_NVIDIA_REBOOT" -eq 1 ]]; then
  [[ "$APPLY_CHANGES" -eq 1 ]] || die "--resume-after-nvidia-reboot requires --apply"
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

verify_host_state
mark_setup_complete
banner "Install Complete"
summary_box "What was done" \
  "Profile applied: $PROFILE" \
  "Vast install flow finished" \
  "Requested extras were installed" \
  "Final verification completed"
if [[ "$WITH_VAST_CLI" -eq 1 ]]; then
  echo "Optional next step: set your Vast API key when you are ready."
  command_box "vastai set api-key YOUR_API_KEY && vastai show user"
fi
success "Host setup finished"
