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
  if [[ "${RESUME_AFTER_REBOOT:-0}" -ne 1 ]]; then
    ensure_two_disk_storage_layout
    run_base_system_prep_from_known_good_flow
    return 0
  fi
  install_nvidia_590_open_from_known_good_flow
  install_vast_host_from_known_good_flow
  print_vast_post_install_notes
}
