#!/usr/bin/env bash
set -euo pipefail

storage_partition_for_disk() {
  local disk="$1"
  if [[ "$disk" =~ nvme ]]; then
    printf '%sp1\n' "$disk"
  else
    printf '%s1\n' "$disk"
  fi
}

storage_parent_disk_for_partition() {
  local part="$1" pk
  pk="$(lsblk -no PKNAME "$part" 2>/dev/null | head -n1 || true)"
  [[ -n "$pk" ]] && readlink -f "/dev/$pk"
}

storage_mountpoint_for_source() {
  findmnt -rn -S "$1" -o TARGET 2>/dev/null | head -n1 || true
}

storage_fstype_for_source() {
  lsblk -no FSTYPE "$1" 2>/dev/null | head -n1 || true
}

storage_already_correct() {
  local layout root_size docker_source root_source
  layout="$(classify_layout)"
  root_source="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
  docker_source="$(findmnt -n -o SOURCE /var/lib/docker 2>/dev/null || true)"
  root_size="$(df -BG --output=size / 2>/dev/null | tail -n1 | tr -dc '0-9')"

  case "$layout" in
    single-disk)
      [[ -n "$root_size" && "$root_size" -ge 95 && "$root_size" -le 105 ]] || return 1
      [[ -n "$docker_source" && "$docker_source" != "$root_source" ]] || return 1
      return 0
      ;;
    two-disk)
      [[ -n "$docker_source" && "$docker_source" != "$root_source" ]] || return 1
      return 0
      ;;
    multi-disk)
      [[ -n "$docker_source" && "$docker_source" != "$root_source" ]] || return 1
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

prompt_storage_confirmation() {
  local prompt reply
  prompt="$1"
  prompt_box "$prompt"
  read -r -p "Continue? [y/N]: " reply
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) die "Storage step cancelled by user." ;;
  esac
}

single_disk_partition_prefix() {
  local disk="$1"
  if [[ "$disk" =~ nvme ]]; then
    printf '%sp' "$disk"
  else
    printf '%s' "$disk"
  fi
}

single_disk_root_partition() {
  local root_source
  root_source="$(findmnt -n -o SOURCE /)"
  [[ -n "$root_source" ]] || return 1
  printf '%s\n' "$root_source"
}

single_disk_docker_partition() {
  local disk="$1"
  if [[ "$disk" =~ nvme ]]; then
    printf '%sp3\n' "$disk"
  else
    printf '%s3\n' "$disk"
  fi
}

plan_storage_layout() {
  local layout root_disk data_disk
  layout="$(classify_layout)"
  root_disk="$(get_root_disk || echo unknown)"
  data_disk="$(largest_non_root_disk || echo none)"

  case "$layout" in
    single-disk)
      echo "STORAGE_PLAN=single-disk"
      echo "ROOT_DISK=$root_disk"
      echo "ROOT_PARTITION=$(single_disk_root_partition || echo unknown)"
      echo "ROOT_TARGET_SIZE_GB=100"
      echo "DOCKER_DATA_DISK=$root_disk"
      echo "DOCKER_DATA_PARTITION=$(single_disk_docker_partition "$root_disk")"
      echo "DOCKER_DATA_TARGET=/var/lib/docker"
      echo "DATA_FS=xfs"
      echo "PLAN_NOTE=shrink root to 100G and use the remaining space on the same disk for /var/lib/docker"
      ;;
    two-disk)
      local part
      part="$(storage_partition_for_disk "$data_disk")"
      echo "STORAGE_PLAN=two-disk"
      echo "ROOT_DISK=$root_disk"
      echo "DATA_DISK=$data_disk"
      echo "DATA_PARTITION=$part"
      echo "DATA_FS=xfs"
      echo "DOCKER_DATA_DISK=$data_disk"
      echo "DOCKER_DATA_TARGET=/var/lib/docker"
      echo "VAST_DATA_TARGET=/var/lib/docker"
      echo "PLAN_NOTE=keep OS on root disk, create one XFS partition on largest non-root disk, mount it at /var/lib/docker"
      ;;
    multi-disk)
      local data_disks data_count
      data_disks="$(list_non_root_disks_by_size_asc | paste -sd, -)"
      data_count="$(list_non_root_disks_by_size_asc | awk 'END {print NR+0}')"
      echo "STORAGE_PLAN=multi-disk-raid0"
      echo "ROOT_DISK=$root_disk"
      echo "DATA_DISKS=$data_disks"
      echo "DATA_DISK_COUNT=$data_count"
      echo "DATA_FS=xfs"
      echo "DOCKER_DATA_TARGET=/var/lib/docker"
      echo "VAST_DATA_TARGET=/var/lib/docker"
      if [[ "$data_count" -ge 2 ]]; then
        echo "RAID_DEVICE=/dev/md0"
        echo "RAID_LEVEL=0"
        echo "PLAN_NOTE=keep OS on root disk, create RAID0 across all non-root internal disks, format XFS, mount at /var/lib/docker"
      else
        echo "PLAN_NOTE=keep OS on root disk, format the only non-root internal disk as XFS, mount at /var/lib/docker"
      fi
      ;;
    *)
      echo "STORAGE_PLAN=ambiguous"
      echo "ROOT_DISK=$root_disk"
      echo "DATA_DISK=$data_disk"
      echo "PLAN_NOTE=manual operator review required"
      ;;
  esac
}

apply_storage_layout_placeholder() {
  local layout data_disk root_disk docker_part
  layout="$(classify_layout)"
  data_disk="$(largest_non_root_disk || true)"
  root_disk="$(get_root_disk || true)"
  case "$layout" in
    single-disk)
      docker_part="$(single_disk_docker_partition "$root_disk")"
      log "single-disk plan: shrink root filesystem to 100G on $root_disk"
      log "single-disk plan: create $docker_part from remaining space"
      log "single-disk plan: format $docker_part as XFS and mount at /var/lib/docker"
      ;;
    two-disk)
      local part
      part="$(storage_partition_for_disk "$data_disk")"
      log "two-disk plan: would prepare $data_disk"
      log "two-disk plan: would create partition $part if missing"
      log "two-disk plan: would format $part as XFS if needed"
      log "two-disk plan: would mount $part at /var/lib/docker and persist in /etc/fstab"
      ;;
    multi-disk)
      local data_disks data_count
      data_disks="$(list_non_root_disks_by_size_asc | paste -sd, -)"
      data_count="$(list_non_root_disks_by_size_asc | awk 'END {print NR+0}')"
      if [[ "$data_count" -ge 2 ]]; then
        log "multi-disk plan: would create RAID0 /dev/md0 across: $data_disks"
        log "multi-disk plan: would format /dev/md0 as XFS and mount at /var/lib/docker"
      else
        log "multi-disk plan: would format the single non-root data disk as XFS and mount at /var/lib/docker"
      fi
      ;;
    *)
      die "Ambiguous storage layout; refusing to guess in v1"
      ;;
  esac
}

ensure_multi_disk_raid0_storage_layout() {
  local layout mount_target data_count uuid raid_device part data_disk
  local -a data_disks parts
  layout="$(classify_layout)"
  mount_target="/var/lib/docker"
  raid_device="/dev/md0"

  if [[ "$layout" != "multi-disk" ]]; then
    die "multi-disk RAID0 storage apply requested, but layout is $layout"
  fi

  mapfile -t data_disks < <(list_non_root_disks_by_size_asc)
  data_count="${#data_disks[@]}"
  [[ "$data_count" -ge 1 ]] || die "no non-root data disks found"

  if [[ "$data_count" -eq 1 ]]; then
    data_disk="${data_disks[0]}"
    part="$(storage_partition_for_disk "$data_disk")"
    prompt_storage_confirmation "Detected MULTI-DISK machine with one non-root data disk. Plan: keep Ubuntu on $(get_root_disk), wipe $data_disk, create one XFS partition, and mount it at $mount_target."
    sudo apt-get update
    sudo apt-get install -y xfsprogs gdisk
    sudo umount "$mount_target" >/dev/null 2>&1 || true
    sudo parted -s "$data_disk" mklabel gpt
    sudo parted -s "$data_disk" mkpart primary xfs 0% 100%
    sudo partprobe "$data_disk"
    sleep 2
    sudo mkfs.xfs -f "$part"
    uuid="$(sudo blkid -s UUID -o value "$part")"
    [[ -n "$uuid" ]] || die "could not resolve UUID for $part"
  else
    prompt_storage_confirmation "Detected MULTI-DISK machine. Plan: keep Ubuntu on $(get_root_disk), wipe all non-root internal disks (${data_disks[*]}), create RAID0 $raid_device, format it as XFS, and mount it at $mount_target."
    sudo apt-get update
    sudo apt-get install -y mdadm xfsprogs gdisk
    sudo umount "$mount_target" >/dev/null 2>&1 || true
    sudo mdadm --stop "$raid_device" >/dev/null 2>&1 || true
    sudo mdadm --remove "$raid_device" >/dev/null 2>&1 || true
    parts=()
    for data_disk in "${data_disks[@]}"; do
      part="$(storage_partition_for_disk "$data_disk")"
      sudo wipefs -a "$data_disk" || true
      sudo parted -s "$data_disk" mklabel gpt
      sudo parted -s "$data_disk" mkpart primary 0% 100%
      sudo parted -s "$data_disk" set 1 raid on || true
      sudo partprobe "$data_disk"
      parts+=("$part")
    done
    sleep 2
    sudo mdadm --create "$raid_device" --metadata=1.2 --level=0 --raid-devices="$data_count" "${parts[@]}"
    sudo udevadm settle || true
    sudo mkfs.xfs -f "$raid_device"
    sudo mkdir -p /etc/mdadm
    sudo mdadm --detail --scan | sudo tee /etc/mdadm/mdadm.conf >/dev/null
    sudo update-initramfs -u || true
    uuid="$(sudo blkid -s UUID -o value "$raid_device")"
    [[ -n "$uuid" ]] || die "could not resolve UUID for $raid_device"
  fi

  sudo mkdir -p "$mount_target"
  sudo cp /etc/fstab "/etc/fstab.vast-host-installer.$(date +%Y%m%d-%H%M%S)"
  sudo python3 - <<PY
from pathlib import Path
p = Path('/etc/fstab')
mount_target = '${mount_target}'
entry = 'UUID=${uuid} ${mount_target} xfs defaults,nofail,prjquota 0 2'
lines = [line for line in p.read_text().splitlines() if mount_target not in line]
lines.append(entry)
p.write_text('\n'.join(lines) + '\n')
PY
  sudo mount -a
  log "multi-disk storage layout applied -> $mount_target"
}

ensure_single_disk_storage_layout() {
  local root_disk root_part prefix bios_part docker_part uuid mount_target
  root_disk="$(get_root_disk)"
  root_part="$(single_disk_root_partition)"
  prefix="$(single_disk_partition_prefix "$root_disk")"
  bios_part="${prefix}1"
  docker_part="${prefix}3"
  mount_target="/var/lib/docker"

  [[ "$(classify_layout)" == "single-disk" ]] || die "single-disk storage apply requested, but layout is $(classify_layout)"
  [[ -b "$root_disk" ]] || die "root disk not found: $root_disk"
  [[ -b "$root_part" ]] || die "root partition not found: $root_part"

  prompt_storage_confirmation "Detected SINGLE-DISK machine. Plan: keep Ubuntu on $root_part at 100G, create $docker_part from remaining space, format it as XFS, and mount it at $mount_target."

  sudo apt install -y cloud-guest-utils e2fsprogs gdisk
  sudo e2fsck -f -y "$root_part"
  sudo resize2fs "$root_part" 100G
  sudo parted -s "$root_disk" unit GiB resizepart 2 100
  sudo parted -s "$root_disk" unit GiB mkpart primary xfs 100 100%
  sudo partprobe "$root_disk"
  sleep 2
  sudo mkfs.xfs -f "$docker_part"

  uuid="$(sudo blkid -s UUID -o value "$docker_part")"
  [[ -n "$uuid" ]] || die "could not resolve UUID for $docker_part"

  sudo mkdir -p "$mount_target"
  sudo cp /etc/fstab "/etc/fstab.vast-host-installer.$(date +%Y%m%d-%H%M%S)"
  sudo python3 - <<PY
from pathlib import Path
p = Path('/etc/fstab')
mount_target = '${mount_target}'
entry = 'UUID=${uuid} ${mount_target} xfs defaults,nofail,prjquota 0 2'
lines = [line for line in p.read_text().splitlines() if mount_target not in line]
lines.append(entry)
p.write_text('\n'.join(lines) + '\n')
PY
  sudo mount -a
  log "single-disk storage layout applied: $docker_part -> $mount_target"
}

ensure_two_disk_storage_layout() {
  local layout data_disk part uuid mount_target
  layout="$(classify_layout)"
  data_disk="$(largest_non_root_disk || true)"
  mount_target="/var/lib/docker"

  if [[ "$layout" != "two-disk" ]]; then
    die "two-disk storage apply requested, but layout is $layout"
  fi
  [[ -b "$data_disk" ]] || die "data disk not found: $data_disk"
  [[ -n "${CONFIRM_DISK:-}" ]] || die "Refusing destructive two-disk apply without --confirm-disk ${data_disk}"
  [[ "$CONFIRM_DISK" == "$data_disk" ]] || die "Refusing destructive two-disk apply: expected --confirm-disk ${data_disk}, got ${CONFIRM_DISK}"

  part="$(storage_partition_for_disk "$data_disk")"
  prompt_storage_confirmation "Detected TWO-DISK machine. Plan: keep Ubuntu on $layout root disk, use $data_disk for /var/lib/docker, create one XFS partition, and mount it persistently."
  log "applying two-disk storage layout on $data_disk"

  if ! blkid "$part" >/dev/null 2>&1; then
    log "creating GPT + single XFS partition on $data_disk"
    sudo parted -s "$data_disk" mklabel gpt
    sudo parted -s "$data_disk" mkpart primary xfs 0% 100%
    sudo partprobe "$data_disk"
    sleep 2
    sudo mkfs.xfs -f "$part"
  else
    log "partition already exists: $part"
  fi

  uuid="$(sudo blkid -s UUID -o value "$part")"
  [[ -n "$uuid" ]] || die "could not resolve UUID for $part"

  sudo mkdir -p "$mount_target"
  sudo cp /etc/fstab "/etc/fstab.vast-host-installer.$(date +%Y%m%d-%H%M%S)"
  sudo python3 - <<PY
from pathlib import Path
p = Path('/etc/fstab')
mount_target = '${mount_target}'
entry = 'UUID=${uuid} ${mount_target} xfs defaults,nofail,prjquota 0 2'
lines = [line for line in p.read_text().splitlines() if mount_target not in line]
lines.append(entry)
p.write_text('\n'.join(lines) + '\n')
PY
  sudo mount -a
  log "two-disk storage layout applied: $part -> $mount_target"
}
