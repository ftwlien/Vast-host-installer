#!/usr/bin/env bash
set -euo pipefail

run_profile_fresh_basic() {
  log "profile: fresh-basic"
  print_detection_summary
  plan_storage_layout
  log "v1 engine note: using known-good prep modules where possible, still non-final"
  if [[ "${RESUME_AFTER_NVIDIA_REBOOT:-0}" -ne 1 ]]; then
    return 0
  fi
  install_vast_host_from_known_good_flow
  print_vast_post_install_notes
}
