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

plan_storage_layout() {
  local layout root_disk data_disk
  layout="$(classify_layout)"
  root_disk="$(get_root_disk || echo unknown)"
  data_disk="$(largest_non_root_disk || echo none)"

  case "$layout" in
    single-disk)
      echo "STORAGE_PLAN=single-disk"
      echo "ROOT_DISK=$root_disk"
      echo "DATA_DISK=$root_disk"
      echo "DOCKER_DATA_TARGET=/var/lib/docker"
      echo "VAST_DATA_TARGET=/var/lib/docker"
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
    *)
      echo "STORAGE_PLAN=ambiguous"
      echo "ROOT_DISK=$root_disk"
      echo "DATA_DISK=$data_disk"
      echo "PLAN_NOTE=manual operator review required"
      ;;
  esac
}

apply_storage_layout_placeholder() {
  local layout data_disk part
  layout="$(classify_layout)"
  data_disk="$(largest_non_root_disk || true)"
  case "$layout" in
    single-disk)
      log "placeholder: single-disk mode will keep Docker/Vast on the existing root disk"
      ;;
    two-disk)
      part="$(storage_partition_for_disk "$data_disk")"
      log "two-disk plan: would prepare $data_disk"
      log "two-disk plan: would create partition $part if missing"
      log "two-disk plan: would format $part as XFS if needed"
      log "two-disk plan: would mount $part at /var/lib/docker and persist in /etc/fstab"
      ;;
    *)
      die "Ambiguous storage layout; refusing to guess in v1"
      ;;
  esac
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
