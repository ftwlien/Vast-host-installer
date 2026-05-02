#!/usr/bin/env bash
set -euo pipefail

run_profile_fresh_basic() {
  log "profile: fresh-basic"
  print_detection_summary
  plan_storage_layout
  log "v1 engine note: using known-good prep modules where possible, still non-final"
  if [[ "${RESUME_AFTER_REBOOT:-0}" -ne 1 ]]; then
    apply_storage_layout_placeholder
    run_base_system_prep_from_known_good_flow
    return 0
  fi
  install_nvidia_590_open_from_known_good_flow
  install_vast_host_from_known_good_flow
  print_vast_post_install_notes
}
