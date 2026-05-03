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
      echo "PLAN_STORAGE=use 100G for / and the rest for /var/lib/docker on the root disk"
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
      echo "Storage action: shrink root filesystem to 100G and use the remaining space on the same disk for /var/lib/docker"
      ;;
    two-disk)
      echo "Storage action: create one XFS partition on ${data_disk}, mount it at /var/lib/docker, persist in /etc/fstab"
      echo "Required apply confirmation: --confirm-disk ${data_disk}"
      ;;
    *)
      echo "Storage action: STOP — layout is ambiguous and needs operator review"
      ;;
  esac

  echo "Phase 1: system prep = apt update/upgrade/dist-upgrade, disable unattended apt jobs, install base packages"
  echo "Phase 2 after reboot: install/configure NVIDIA open drivers, then reboot again"
  echo "Phase 3 after second reboot: verify nvidia-smi, run Vast install command, set host port range, then verify services"
  echo "Docker: not preinstalled by default; let Vast setup own Docker unless fallback is needed"
  echo "Reboot expectation: one reboot after prep, one reboot after NVIDIA setup"
}
