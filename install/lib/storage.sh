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

storage_format_existing_partition_for_docker() {
  local part="$1" mount fstype opts uuid backup
  [[ -b "$part" ]] || die "selected partition does not exist: $part"
  mount="$(storage_mountpoint_for_source "$part")"
  fstype="$(storage_fstype_for_source "$part")"

  if [[ "$mount" == "/var/lib/docker" ]]; then
    opts="$(findmnt -no OPTIONS /var/lib/docker 2>/dev/null || true)"
    if [[ "$fstype" == "xfs" && "$opts" == *prjquota* ]]; then
      log "$part is already mounted at /var/lib/docker as XFS with prjquota; skipping storage changes"
      return 0
    fi
    warn "$part is mounted at /var/lib/docker but is not XFS with prjquota; it must be reformatted to match Vast storage policy."
  elif [[ -n "$mount" ]]; then
    die "$part is mounted at $mount. Unmount it or choose another partition."
  fi

  prompt_box "This will WIPE $part, format it as XFS, and mount it at /var/lib/docker with prjquota."
  echo "Type exactly: WIPE $part"
  read -r confirm
  [[ "$confirm" == "WIPE $part" ]] || die "Typed confirmation did not match; refusing partition wipe."

  sudo apt install -y xfsprogs util-linux
  sudo systemctl stop docker 2>/dev/null || true
  sudo systemctl stop containerd 2>/dev/null || true
  if findmnt /var/lib/docker >/dev/null 2>&1; then
    sudo umount /var/lib/docker || true
  fi
  if [[ -d /var/lib/docker && ! -L /var/lib/docker ]] && [[ -n "$(find /var/lib/docker -mindepth 1 -maxdepth 1 2>/dev/null | head -n1 || true)" ]]; then
    backup="/var/lib/docker.before-vast-host-installer.$(date +%Y%m%d-%H%M%S)"
    log "moving existing /var/lib/docker to $backup"
    sudo mv /var/lib/docker "$backup"
  fi
  sudo mkdir -p /var/lib/docker
  sudo chmod 0711 /var/lib/docker
  sudo wipefs -a "$part"
  sudo mkfs.xfs -f "$part"
  uuid="$(sudo blkid -s UUID -o value "$part")"
  [[ -n "$uuid" ]] || die "could not resolve UUID for $part"
  sudo cp /etc/fstab "/etc/fstab.vast-host-installer.$(date +%Y%m%d-%H%M%S)"
  sudo python3 - <<PY
from pathlib import Path
p = Path('/etc/fstab')
entry = 'UUID=${uuid} /var/lib/docker xfs defaults,nofail,pquota,prjquota 0 2'
lines = [line for line in p.read_text().splitlines() if ' /var/lib/docker ' not in line]
lines.append(entry)
p.write_text('\n'.join(lines) + '\n')
PY
  sudo mount /var/lib/docker
  opts="$(findmnt -no OPTIONS /var/lib/docker)"
  [[ "$(findmnt -no FSTYPE /var/lib/docker)" == "xfs" && "$opts" == *prjquota* ]] || die "failed to mount /var/lib/docker as XFS with prjquota"
  log "$part is ready for Docker/Vast storage at /var/lib/docker"
}

official_ubuntu_storage_wizard() {
  local root root_src root_real all_disks all_parts nonroot_count biggest biggest_size d size i part mount fstype parent choice confirm whole_disk_choice stop_choice
  root="$(get_root_disk)"
  root_src="$(findmnt -n -o SOURCE /)"
  root_real="$(readlink -f "$root_src")"
  mapfile -t all_disks < <(lsblk -dn -o PATH,TYPE | awk '$2=="disk" {print $1}' | xargs -r -n1 readlink -f | sort -u)
  mapfile -t all_parts < <(lsblk -ln -o PATH,TYPE | awk '$2=="part" {print $1}' | xargs -r -n1 readlink -f | sort -u)

  question "Storage setup"
  prompt_box "Official Ubuntu mode detected. The installer will look and continue like the ISO flow, but storage rules are stricter because Ubuntu is already installed. It will never live-repartition the mounted root disk."
  lsblk -e7 -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL

  nonroot_count=0
  biggest=""
  biggest_size=0
  for d in "${all_disks[@]}"; do
    [[ "$d" == "$root" ]] && continue
    nonroot_count=$((nonroot_count + 1))
    size="$(blockdev --getsize64 "$d" 2>/dev/null || echo 0)"
    if (( size > biggest_size )); then
      biggest="$d"
      biggest_size="$size"
    fi
  done

  echo
  echo "Storage choices:"
  i=1
  for part in "${all_parts[@]}"; do
    [[ "$part" == "$root_real" ]] && continue
    mount="$(storage_mountpoint_for_source "$part")"
    [[ "$mount" == "/" || "$mount" == "/boot" || "$mount" == "/boot/efi" || "$mount" == "[SWAP]" ]] && continue
    parent="$(storage_parent_disk_for_partition "$part")"
    fstype="$(storage_fstype_for_source "$part")"
    printf '  %d) Use existing partition %-14s parent=%s fstype=%s mount=%s\n' "$i" "$part" "${parent:-unknown}" "${fstype:-none}" "${mount:-none}"
    i=$((i + 1))
  done

  if (( ${#all_disks[@]} == 2 && nonroot_count == 1 )); then
    printf '  %d) Wipe whole non-root data disk %s and mount it at /var/lib/docker\n' "$i" "$biggest"
    whole_disk_choice="$i"
    i=$((i + 1))
  else
    whole_disk_choice=""
  fi
  stop_choice="$i"
  printf '  %d) Stop/cancel and show required Ubuntu partition layout\n' "$stop_choice"

  echo
  read -r -p "Choose storage option number: " choice
  [[ "$choice" =~ ^[0-9]+$ ]] || die "Invalid storage choice."

  i=1
  for part in "${all_parts[@]}"; do
    [[ "$part" == "$root_real" ]] && continue
    mount="$(storage_mountpoint_for_source "$part")"
    [[ "$mount" == "/" || "$mount" == "/boot" || "$mount" == "/boot/efi" || "$mount" == "[SWAP]" ]] && continue
    if [[ "$choice" == "$i" ]]; then
      storage_format_existing_partition_for_docker "$part"
      return 0
    fi
    i=$((i + 1))
  done

  if [[ -n "$whole_disk_choice" && "$choice" == "$whole_disk_choice" ]]; then
    [[ -b "$biggest" ]] || die "data disk not found: $biggest"
    prompt_box "This will WIPE the whole non-root disk $biggest and use it for /var/lib/docker. Root disk $root will not be touched."
    echo "Type exactly: WIPE $biggest"
    read -r confirm
    [[ "$confirm" == "WIPE $biggest" ]] || die "Typed confirmation did not match; refusing storage wipe."
    CONFIRM_DISK="$biggest"
    ensure_two_disk_storage_layout
    return 0
  fi

  if [[ "$choice" == "$stop_choice" ]]; then
    cat <<'EOF'

Required 1-disk official-Ubuntu layout:
  EFI:              1G
  /:                100G ext4
  /var/lib/docker:  rest of disk, separate partition

Create that during Ubuntu install, then rerun:
  sudo /opt/vast-host-installer/bin/vast-host-installer --first-run --official-ubuntu
EOF
    die "Storage setup cancelled. Reinstall/partition Ubuntu first for the production 1-disk layout."
  fi
  die "Invalid storage choice."
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
    *)
      die "Ambiguous storage layout; refusing to guess in v1"
      ;;
  esac
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
