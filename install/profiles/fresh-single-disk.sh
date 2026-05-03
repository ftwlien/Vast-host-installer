#!/usr/bin/env bash
set -euo pipefail

run_profile_fresh_single_disk() {
  log "profile: fresh-single-disk"
  print_detection_summary
  plan_storage_layout
  if [ "$(classify_layout)" != "single-disk" ]; then
    die "fresh-single-disk selected, but host did not classify cleanly as single-disk"
  fi
  log "v1 engine note: single-disk mode still uses placeholder storage apply"
  if [[ "${RESUME_AFTER_NVIDIA_REBOOT:-0}" -ne 1 ]]; then
    return 0
  fi
  install_vast_host_from_known_good_flow
  print_vast_post_install_notes
}
