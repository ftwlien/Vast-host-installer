#!/usr/bin/env bash
set -euo pipefail

autoinstall_rank_disks() {
  lsblk -b -dn -o NAME,SIZE,TYPE | awk '$3 == "disk" {print "/dev/" $1 "|" $2}' | sort -t'|' -k2,2n
}

autoinstall_smallest_disk() {
  autoinstall_rank_disks | head -n1 | cut -d'|' -f1
}

autoinstall_largest_disk() {
  autoinstall_rank_disks | tail -n1 | cut -d'|' -f1
}

autoinstall_disk_count() {
  autoinstall_rank_disks | wc -l | tr -d ' '
}

autoinstall_layout_classification() {
  local count
  count="$(autoinstall_disk_count)"
  if [[ "$count" -le 1 ]]; then
    echo single-disk
    return 0
  fi
  if [[ "$count" -eq 2 ]]; then
    echo two-disk
    return 0
  fi
  echo ambiguous
}

emit_autoinstall_storage_policy() {
  local layout smallest largest
  layout="$(autoinstall_layout_classification)"
  smallest="$(autoinstall_smallest_disk || true)"
  largest="$(autoinstall_largest_disk || true)"

  echo "AUTOINSTALL_LAYOUT=$layout"
  echo "AUTOINSTALL_SMALLEST_DISK=${smallest:-none}"
  echo "AUTOINSTALL_LARGEST_DISK=${largest:-none}"

  case "$layout" in
    single-disk)
      echo "AUTOINSTALL_OS_DISK=${smallest:-none}"
      echo "AUTOINSTALL_DATA_DISK=${smallest:-none}"
      ;;
    two-disk)
      echo "AUTOINSTALL_OS_DISK=${smallest:-none}"
      echo "AUTOINSTALL_DATA_DISK=${largest:-none}"
      ;;
    *)
      echo "AUTOINSTALL_OS_DISK=undecided"
      echo "AUTOINSTALL_DATA_DISK=undecided"
      ;;
  esac
}
