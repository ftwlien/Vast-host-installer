#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="fresh-basic"
WITH_RIG_MONITOR=0
WITH_GPUTEMPS=0
WITH_FLEET_HEALTH=0
PLAN_ONLY=0
APPLY_CHANGES=0
FIRST_BOOT_MODE=0
CONFIRM_DISK=""
VAST_API_KEY="${VAST_API_KEY:-}"
VAST_PORT_RANGE="${VAST_PORT_RANGE:-40000-40019}"

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
  --with-rig-monitor
  --with-gputemps
  --with-fleet-health
  --vast-api-key <key>
  --vast-port-range <range>
  --confirm-disk <device>
  --detect-only
  --plan-only
  --first-run
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
    --with-rig-monitor)
      WITH_RIG_MONITOR=1
      shift
      ;;
    --with-gputemps)
      WITH_GPUTEMPS=1
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
    --vast-port-range)
      VAST_PORT_RANGE="${2:-}"
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

ensure_basic_tools

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
  run_first_boot_questionnaire
  PROFILE="$(infer_profile_from_layout)"
  VAST_API_KEY="$FIRST_BOOT_API_KEY"
  VAST_PORT_RANGE="$FIRST_BOOT_PORT_RANGE"
  WITH_RIG_MONITOR="$FIRST_BOOT_INSTALL_RIG_MONITOR"
  WITH_GPUTEMPS="$FIRST_BOOT_INSTALL_GPUTEMPS"
  WITH_FLEET_HEALTH="$FIRST_BOOT_INSTALL_FLEET_HEALTH"

  set_final_hostname "$FIRST_BOOT_HOSTNAME"
  ensure_operator_user "$FIRST_BOOT_USERNAME" "$FIRST_BOOT_PASSWORD"

  print_detection_summary
  plan_storage_layout
  emit_autoinstall_storage_policy
  emit_plan_preview "$PROFILE"
  APPLY_CHANGES=1
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

if [[ "$WITH_RIG_MONITOR" -eq 1 ]]; then
  install_rig_monitor_placeholder
fi
if [[ "$WITH_GPUTEMPS" -eq 1 ]]; then
  install_gputemps_placeholder
fi
if [[ "$WITH_FLEET_HEALTH" -eq 1 ]]; then
  install_fleet_health_placeholder
fi

verify_host_state
log "install engine skeleton completed"
