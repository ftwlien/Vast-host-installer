#!/usr/bin/env bash
set -euo pipefail

run_profile_fresh_two_disk() {
  log "profile: fresh-two-disk"
  print_detection_summary
  plan_storage_layout
  if [ "$(classify_layout)" != "two-disk" ]; then
    die "fresh-two-disk selected, but host did not classify cleanly as two-disk"
  fi
  log "v1 engine note: two-disk storage apply is now real; NVIDIA/Docker/Vast flow is still evolving"
  if [[ "${RESUME_AFTER_NVIDIA_REBOOT:-0}" -ne 1 ]]; then
    return 0
  fi
  verify_nvidia_ready_or_die
  install_vast_host_from_known_good_flow
  print_vast_post_install_notes
}
