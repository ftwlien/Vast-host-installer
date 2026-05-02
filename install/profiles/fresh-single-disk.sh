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
  apply_storage_layout_placeholder
  run_base_system_prep_from_known_good_flow
  install_nvidia_590_open_from_known_good_flow
  install_docker_from_known_good_flow
  install_vast_host_from_known_good_flow
  print_vast_post_install_notes
}
