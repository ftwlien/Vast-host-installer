#!/usr/bin/env bash
set -euo pipefail

get_root_source() {
  findmnt -n -o SOURCE /
}

get_root_disk() {
  local src parent
  src="$(get_root_source)"
  [ -n "$src" ] || return 1
  parent="$(lsblk -no PKNAME "$src" 2>/dev/null | head -n1 || true)"
  if [ -n "$parent" ]; then
    printf '/dev/%s\n' "$parent"
    return 0
  fi
  printf '%s\n' "$src"
}

_disk_info_json() {
  lsblk -J -b -o NAME,PATH,PKNAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS,MODEL,RM,TRAN
}

list_candidate_disks() {
  python3 - <<'PY'
import json, subprocess
payload = json.loads(subprocess.check_output(['lsblk','-J','-b','-o','NAME,PATH,PKNAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS,MODEL,RM,TRAN'], text=True))
for dev in payload.get('blockdevices', []):
    if dev.get('type') != 'disk':
        continue
    removable = str(dev.get('rm') or '0') == '1'
    transport = (dev.get('tran') or '').lower()
    role = 'ignored-installer-media' if removable or transport == 'usb' else 'candidate'
    mounts = [m for m in (dev.get('mountpoints') or []) if m]
    print('|'.join([
        dev.get('path') or '',
        str(dev.get('size') or 0),
        dev.get('fstype') or '',
        ','.join(mounts),
        (dev.get('model') or '').strip(),
        str(dev.get('rm') or '0'),
        dev.get('tran') or '',
        role,
    ]))
PY
}

largest_non_root_disk() {
  local root
  root="$(basename "$(get_root_disk || echo '')")"
  lsblk -b -dn -o NAME,SIZE,TYPE,RM,TRAN | awk -v root="$root" '$3 == "disk" && $1 != root && $4 != "1" && tolower($5) != "usb" {print $1 " " $2}' | sort -k2,2nr | head -n1 | awk '{print "/dev/" $1}'
}

count_real_disks() {
  lsblk -dn -o TYPE,RM,TRAN | awk '$1 == "disk" && $2 != "1" && tolower($3) != "usb" {count++} END {print count+0}'
}

classify_layout() {
  local disk_count data_disk
  disk_count="$(count_real_disks)"
  data_disk="$(largest_non_root_disk || true)"
  if [ "$disk_count" -le 1 ]; then
    echo single-disk
    return 0
  fi
  if [ "$disk_count" -eq 2 ] && [ -n "$data_disk" ]; then
    echo two-disk
    return 0
  fi
  echo ambiguous
}

print_detection_summary() {
  echo "ROOT_SOURCE=$(get_root_source || echo unknown)"
  echo "ROOT_DISK=$(get_root_disk || echo unknown)"
  echo "DISK_COUNT=$(count_real_disks)"
  echo "LAYOUT=$(classify_layout)"
  echo "DATA_DISK=$(largest_non_root_disk || echo none)"
  echo "DISKS_BEGIN"
  list_candidate_disks || true
  echo "DISKS_END"
}
