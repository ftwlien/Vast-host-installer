#!/usr/bin/env bash
set -euo pipefail

emit_plan_preview() {
  local profile layout root_disk data_disk auto_layout auto_os_disk auto_data_disk
  profile="$1"
  layout="$(classify_layout)"
  root_disk="$(get_root_disk || echo unknown)"
  data_disk="$(largest_non_root_disk || echo none)"
  auto_layout="$(autoinstall_layout_classification)"
  auto_os_disk="$(autoinstall_smallest_disk || echo none)"
  auto_data_disk="$(autoinstall_largest_disk || echo none)"

  echo "PLAN_PROFILE=$profile"
  echo "PLAN_LAYOUT=$layout"
  echo "PLAN_ROOT_DISK=$root_disk"
  echo "PLAN_DATA_DISK=$data_disk"

  case "$layout" in
    single-disk)
      echo "PLAN_STORAGE=keep OS + Docker/Vast on root disk"
      ;;
    two-disk)
      echo "PLAN_STORAGE=keep OS on root disk; use largest non-root disk for Docker/Vast data"
      ;;
    *)
      echo "PLAN_STORAGE=ambiguous; manual operator review required"
      ;;
  esac

  echo
  echo "==== HUMAN PLAN SUMMARY ===="
  echo "Profile: $profile"
  echo "Layout:  $layout"
  echo "Root:    $root_disk"
  echo "Data:    ${data_disk:-none}"
  echo "Autoinstall view: $auto_layout"
  echo "Autoinstall OS disk target:   ${auto_os_disk:-none}"
  echo "Autoinstall data disk target: ${auto_data_disk:-none}"

  case "$layout" in
    single-disk)
      echo "Storage action: keep Docker/Vast on the existing root disk"
      ;;
    two-disk)
      echo "Storage action: create one XFS partition on ${data_disk}, mount it at /var/lib/docker, persist in /etc/fstab"
      echo "Required apply confirmation: --confirm-disk ${data_disk}"
      ;;
    *)
      echo "Storage action: STOP — layout is ambiguous and needs operator review"
      ;;
  esac

  echo "System prep: apt update/upgrade/dist-upgrade, disable unattended apt jobs, install base packages"
  echo "NVIDIA: install known-good 590-open baseline module path"
  echo "Docker: install Docker CE + enable service + add target user to docker group"
  echo "Vast: run Vast host installer with provided API key and set host port range to ${VAST_PORT_RANGE:-40000-40019}"
  echo "Verify: nvidia-smi, docker active, nvidia runtime, vastai active, host port range, console reachability"
  echo "Reboot expectation: likely required after NVIDIA driver install"
}
