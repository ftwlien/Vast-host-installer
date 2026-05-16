#!/usr/bin/env bash
set -euo pipefail

autoinstall_rank_disks() {
  lsblk -b -dn -o NAME,SIZE,TYPE,RM,TRAN | awk '$3 == "disk" && $4 != "1" && tolower($5) != "usb" {print "/dev/" $1 "|" $2}' | sort -t'|' -k2,2n
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
  echo multi-disk-raid0
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
    multi-disk-raid0)
      echo "AUTOINSTALL_OS_DISK=${smallest:-none}"
      echo "AUTOINSTALL_DATA_DISKS=$(autoinstall_rank_disks | tail -n +2 | cut -d'|' -f1 | paste -sd, -)"
      echo "AUTOINSTALL_RAID_LEVEL=0"
      echo "AUTOINSTALL_RAID_TARGET=/var/lib/docker"
      ;;
    *)
      echo "AUTOINSTALL_OS_DISK=undecided"
      echo "AUTOINSTALL_DATA_DISK=undecided"
      ;;
  esac
}
