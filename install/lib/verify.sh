#!/usr/bin/env bash
set -euo pipefail

verify_host_state() {
  local failed=0
  echo "VERIFY_BEGIN"
  echo "CHECK=nvidia-smi"
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 | sed 's/^/RESULT=driver:/'
  else
    echo "RESULT=nvidia-smi:missing"
    failed=1
  fi

  echo "CHECK=docker"
  if ! command -v docker >/dev/null 2>&1; then
    echo "RESULT=docker:missing"
    failed=1
  elif ! systemctl cat docker >/dev/null 2>&1; then
    echo "RESULT=docker:service-missing"
    failed=1
  elif systemctl is-active docker >/dev/null 2>&1; then
    echo "RESULT=docker:active"
  else
    echo "RESULT=docker:inactive"
    failed=1
  fi

  echo "CHECK=nvidia-runtime"
  if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q 'nvidia'; then
    echo "RESULT=nvidia-runtime:present"
  else
    echo "RESULT=nvidia-runtime:missing"
    failed=1
  fi

  echo "CHECK=vast-service"
  if ! systemctl cat vastai >/dev/null 2>&1; then
    echo "RESULT=vastai:service-missing"
    failed=1
  elif systemctl is-active vastai >/dev/null 2>&1; then
    echo "RESULT=vastai:active"
  else
    echo "RESULT=vastai:inactive"
    failed=1
  fi

  echo "CHECK=vast-port-range"
  if [[ -f /var/lib/vastai_kaalia/host_port_range ]]; then
    printf 'RESULT=host-port-range:%s\n' "$(cat /var/lib/vastai_kaalia/host_port_range 2>/dev/null)"
  else
    echo "RESULT=host-port-range:missing"
    echo "WARN=host-port-range file missing; not failing because Vast interactive setup may own port collection"
  fi

  echo "CHECK=console-reachability"
  if curl -I -fsS https://console.vast.ai >/dev/null 2>&1; then
    echo "RESULT=console:ok"
  else
    echo "RESULT=console:fail"
  fi
  echo "VERIFY_END"
  if [[ "$failed" -ne 0 ]]; then
    die "Final verification failed. Vast setup is not complete; see VERIFY results above."
  fi
}

_mount_fstype() {
  findmnt -n -o FSTYPE "$1" 2>/dev/null || true
}

_mount_source() {
  findmnt -n -o SOURCE "$1" 2>/dev/null || true
}

_source_parent_disk() {
  local source="$1" parent
  source="$(readlink -f "$source" 2>/dev/null || printf '%s' "$source")"
  parent="$(lsblk -no PKNAME "$source" 2>/dev/null | head -n1 || true)"
  if [[ -n "$parent" ]]; then
    printf '/dev/%s\n' "$parent"
  fi
}

_disk_size_bytes() {
  lsblk -b -dn -o SIZE "$1" 2>/dev/null | head -n1 | tr -dc '0-9'
}

_fstab_has_mount() {
  local target="$1"
  awk -v target="$target" '$1 !~ /^#/ && $2 == target {found=1} END {exit found ? 0 : 1}' /etc/fstab 2>/dev/null
}

preflight_storage_layout() {
  local failed=0 root_source root_disk root_fstype efi_source efi_fstype docker_source docker_fstype docker_disk root_disk_size
  local split_min_bytes=$((140 * 1024 * 1024 * 1024))

  echo "CHECK=storage-root"
  root_source="$(_mount_source /)"
  root_disk="$(get_root_disk || true)"
  root_fstype="$(_mount_fstype /)"
  if [[ -n "$root_source" && -n "$root_disk" && -n "$root_fstype" ]]; then
    echo "RESULT=root:${root_source}:${root_fstype}:disk=${root_disk}"
  else
    echo "RESULT=root:missing"
    failed=1
  fi

  echo "CHECK=storage-efi"
  efi_source="$(_mount_source /boot/efi)"
  efi_fstype="$(_mount_fstype /boot/efi)"
  if [[ -n "$efi_source" && "$efi_fstype" =~ ^(vfat|fat|fat32)$ ]]; then
    echo "RESULT=efi:${efi_source}:${efi_fstype}"
  else
    echo "RESULT=efi:missing-or-wrong-fstype:${efi_fstype:-none}"
    failed=1
  fi

  echo "CHECK=storage-fstab"
  if _fstab_has_mount / && _fstab_has_mount /boot/efi; then
    echo "RESULT=fstab:root-and-efi-present"
  else
    echo "RESULT=fstab:missing-root-or-efi"
    failed=1
  fi

  echo "CHECK=storage-docker"
  docker_source="$(_mount_source /var/lib/docker)"
  docker_fstype="$(_mount_fstype /var/lib/docker)"
  docker_disk=""
  if [[ -n "$docker_source" ]]; then
    docker_disk="$(_source_parent_disk "$docker_source")"
  fi

  if [[ "${OFFICIAL_UBUNTU_MODE:-0}" -eq 1 ]]; then
    echo "RESULT=docker:official-ubuntu-deferred-to-vast:source=${docker_source:-not-mounted}:fstype=${docker_fstype:-none}"
    echo "WARN=official Ubuntu mode leaves Docker/Vast storage layout to the official Vast installer/tooling; split-storage preflight is not enforced"
    return "$failed"
  fi

  case "${PROFILE:-fresh-basic}" in
    fresh-two-disk)
      if [[ -n "$docker_source" && "$docker_source" != "$root_source" && "$docker_disk" != "$root_disk" && "$docker_fstype" == "xfs" ]] && _fstab_has_mount /var/lib/docker; then
        echo "RESULT=docker:two-disk-ok:${docker_source}:${docker_fstype}:disk=${docker_disk}"
      elif [[ -n "$docker_source" && "$docker_source" != "$root_source" && "$docker_disk" == "$root_disk" && "$docker_fstype" == "xfs" ]] && _fstab_has_mount /var/lib/docker; then
        echo "RESULT=docker:two-disk-profile-single-disk-split-ok:${docker_source}:${docker_fstype}:disk=${docker_disk}"
        echo "WARN=profile says fresh-two-disk, but Docker is mounted on a separate XFS partition on the root disk. This is usable, so Phase 3 is allowed to continue."
      else
        echo "RESULT=docker:two-disk-bad:source=${docker_source:-missing}:fstype=${docker_fstype:-missing}:disk=${docker_disk:-unknown}:root_disk=${root_disk:-unknown}"
        failed=1
      fi
      ;;
    fresh-single-disk)
      root_disk_size="$(_disk_size_bytes "$root_disk")"
      if [[ -n "$docker_source" ]]; then
        if [[ "$docker_source" != "$root_source" && "$docker_disk" == "$root_disk" && "$docker_fstype" == "xfs" ]] && _fstab_has_mount /var/lib/docker; then
          echo "RESULT=docker:single-disk-split-ok:${docker_source}:${docker_fstype}:disk=${docker_disk}"
        else
          echo "RESULT=docker:single-disk-split-bad:source=${docker_source:-missing}:fstype=${docker_fstype:-missing}:disk=${docker_disk:-unknown}:root_disk=${root_disk:-unknown}"
          failed=1
        fi
      elif [[ -n "$root_disk_size" && "$root_disk_size" -lt "$split_min_bytes" ]]; then
        echo "RESULT=docker:single-disk-root-only-ok:disk-size=${root_disk_size}"
      else
        echo "RESULT=docker:single-disk-missing-split:disk-size=${root_disk_size:-unknown}"
        failed=1
      fi
      ;;
    *)
      if [[ -n "$docker_source" ]]; then
        echo "RESULT=docker:present:${docker_source}:${docker_fstype:-unknown}"
      else
        echo "RESULT=docker:not-mounted-for-profile:${PROFILE:-unknown}"
        echo "WARN=docker mount not enforced for this profile"
      fi
      ;;
  esac

  return "$failed"
}

phase3_machine_id_menu() {
  local choice machine_id_file="/var/lib/vastai_kaalia/machine_id" restored_id
  [[ -t 0 ]] || return 0
  while true; do
    banner "Before Vast.ai Install/Register"
    echo "If this is a reinstall/replacement and you saved the old Vast machine ID, restore it now."
    echo "If this is a new host, skip restore and Vast will create a new identity."
    echo
    echo "Current machine ID: $(cat "$machine_id_file" 2>/dev/null || echo none)"
    echo
    echo "[1] Run Phase 3 preflight checks"
    echo "[2] Restore preserved Vast machine ID first"
    echo "[3] Show current Vast machine ID"
    echo "[4] Show Phase 3 install command"
    read -r -p "Choice [1]: " choice
    choice="${choice:-1}"
    case "$choice" in
      1) return 0 ;;
      2)
        read -r -p "Paste existing Vast machine_id: " restored_id
        if [[ -z "$restored_id" ]]; then
          warn "Machine ID was empty; nothing restored."
          continue
        fi
        if [[ ! "$restored_id" =~ ^[A-Za-z0-9._:-]+$ ]]; then
          warn "Machine ID contains unexpected characters; refusing to write it."
          continue
        fi
        sudo install -d -m 0755 /var/lib/vastai_kaalia
        printf '%s' "$restored_id" | sudo tee "$machine_id_file" >/dev/null
        sudo chmod 0644 "$machine_id_file"
        success "Restored Vast machine ID before Vast install/register: $(cat "$machine_id_file")"
        ;;
      3)
        if [[ -f "$machine_id_file" ]]; then
          echo "Vast machine ID: $(cat "$machine_id_file")"
        else
          echo "No Vast machine ID found yet."
        fi
        ;;
      4)
        command_box "sudo /opt/vast-host-installer/bin/vast-host-installer --resume"
        ;;
      *) warn "Unknown choice: $choice" ;;
    esac
  done
}

preflight_phase3() {
  local failed=0 next_phase="" nvidia_ready=0
  phase3_machine_id_menu
  banner "Phase 3 Preflight Check"

  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    nvidia_ready=1
  fi

  echo "CHECK=resume-state"
  if [[ -f /var/lib/vast-host-installer/resume.env ]]; then
    # shellcheck disable=SC1091
    source /var/lib/vast-host-installer/resume.env
    next_phase="${NEXT_PHASE:-}"
    if [[ "$next_phase" == "after-nvidia-reboot" ]]; then
      echo "RESULT=resume-state:phase3-ready:profile=${PROFILE:-unknown}"
    elif [[ "$next_phase" == "after-reboot" && "$nvidia_ready" -eq 1 ]]; then
      echo "RESULT=resume-state:phase2-state-but-nvidia-ready:profile=${PROFILE:-unknown}"
      echo "WARN=resume state still pointed at Phase 2, but NVIDIA is already working; advancing to Phase 3 state"
      save_resume_state after-nvidia-reboot
      NEXT_PHASE=after-nvidia-reboot
    else
      echo "RESULT=resume-state:unexpected:${next_phase:-missing-next-phase}"
      failed=1
    fi
  else
    echo "RESULT=resume-state:missing"
    failed=1
  fi

  echo "CHECK=nvidia-smi"
  if [[ "$nvidia_ready" -eq 1 ]]; then
    nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 | sed 's/^/RESULT=driver:/'
  else
    echo "RESULT=nvidia-smi:failed"
    failed=1
  fi

  echo "CHECK=nvidia-module"
  if lsmod | awk '{print $1}' | grep -qx 'nvidia'; then
    echo "RESULT=nvidia-module:loaded"
  else
    echo "RESULT=nvidia-module:not-loaded"
    failed=1
  fi

  echo "CHECK=vast-machine-id"
  if [[ -f /var/lib/vastai_kaalia/machine_id && -s /var/lib/vastai_kaalia/machine_id ]]; then
    echo "RESULT=vast-machine-id:present:$(cat /var/lib/vastai_kaalia/machine_id)"
  else
    echo "RESULT=vast-machine-id:not-present"
    echo "WARN=no preserved Vast machine ID found; Vast.ai will create/register a new identity"
  fi

  echo "CHECK=vast-power-limit"
  if [[ -f /etc/default/vast-nvidia-power-limit ]]; then
    sed 's/^/RESULT=/' /etc/default/vast-nvidia-power-limit
  else
    echo "RESULT=vast-power-limit:not-configured"
    echo "INFO=persistent GPU power limit is optional and not enabled by default"
  fi

  echo "CHECK=secure-boot"
  if command -v mokutil >/dev/null 2>&1; then
    if mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
      echo "RESULT=secure-boot:enabled"
      echo "WARN=secure boot is enabled; NVIDIA may be blocked unless modules are signed/enrolled"
    else
      echo "RESULT=secure-boot:not-enabled"
    fi
  else
    echo "RESULT=secure-boot:mokutil-missing"
  fi

  echo "CHECK=console-reachability"
  if curl -I -fsS https://console.vast.ai >/dev/null 2>&1; then
    echo "RESULT=console:ok"
  else
    echo "RESULT=console:fail"
    failed=1
  fi

  preflight_storage_layout || failed=1

  if [[ "$failed" -eq 0 ]]; then
    success_banner "READY FOR PHASE 3"
    echo "Final pre-Vast install summary:"
    echo "  Machine ID: $(cat /var/lib/vastai_kaalia/machine_id 2>/dev/null || echo missing/new identity)"
    echo "  Port range: $(cat /var/lib/vastai_kaalia/host_port_range 2>/dev/null || echo missing)"
    echo "  Power limit: $(cat /etc/default/vast-nvidia-power-limit 2>/dev/null || echo not configured)"
    echo "  NVIDIA persistence mode: $(nvidia-smi --query-gpu=persistence_mode --format=csv,noheader 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//' || echo unknown)"
    echo
    if [[ -t 0 ]]; then
      read -r -p "Continue to Vast.ai install/register with this state? [y/N]: " confirm_phase3
      case "$confirm_phase3" in
        y|Y|yes|YES) ;;
        *) echo "Cancelled. Re-run --preflight-phase3 when ready."; exit 0 ;;
      esac
    fi
    command_box "sudo /opt/vast-host-installer/bin/vast-host-installer --resume"
  else
    die "Phase 3 preflight failed. Fix the failed checks above before running --resume."
  fi
}
