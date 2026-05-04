#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Disk:
    path: str
    size_bytes: int


GIB = 1024 ** 3
SINGLE_DISK_SPLIT_MIN_BYTES = 140 * GIB


def _lsblk_disks() -> list[Disk]:
    output = subprocess.check_output(
        ['lsblk', '-b', '-J', '-o', 'PATH,SIZE,TYPE,MOUNTPOINTS'],
        text=True,
    )
    return _parse_lsblk_disks(output)


def _has_install_media_mount(device: dict) -> bool:
    mountpoints = device.get('mountpoints') or []
    for mountpoint in mountpoints:
        if mountpoint == '/cdrom' or str(mountpoint).startswith('/cdrom/'):
            return True
    return any(_has_install_media_mount(child) for child in device.get('children') or [])


def _parse_lsblk_disks(output: str) -> list[Disk]:
    payload = json.loads(output)
    disks: list[Disk] = []
    for device in payload.get('blockdevices') or []:
        if device.get('type') != 'disk':
            continue
        if _has_install_media_mount(device):
            continue
        disks.append(Disk(path=str(device['path']), size_bytes=int(device['size'])))
    return sorted(disks, key=lambda disk: (disk.size_bytes, disk.path))


def detect_mode() -> str:
    disks = _lsblk_disks()
    if len(disks) == 1:
        return 'single-disk'
    if len(disks) >= 2:
        return 'two-disk'
    raise RuntimeError(
        'ambiguous storage layout: no installable disks found'
    )


def _is_uefi_boot() -> bool:
    return Path('/sys/firmware/efi').exists()


def _single_disk_tail(split_docker: bool) -> str:
    if split_docker:
        return """
    - type: partition
      id: root-partition
      device: os-disk
      size: 100G
    - type: format
      id: root-format
      volume: root-partition
      fstype: ext4
    - type: mount
      id: root-mount
      path: /
      device: root-format
    - type: partition
      id: docker-partition
      device: os-disk
      size: -1
    - type: format
      id: docker-format
      volume: docker-partition
      fstype: xfs
    - type: mount
      id: docker-mount
      path: /var/lib/docker
      device: docker-format
      options: defaults,prjquota
""".lstrip('\n').rstrip()

    return """
    - type: partition
      id: root-partition
      device: os-disk
      size: -1
    - type: format
      id: root-format
      volume: root-partition
      fstype: ext4
    - type: mount
      id: root-mount
      path: /
      device: root-format
""".lstrip('\n').rstrip()


def _disk_locator_yaml(path: str | None, fallback_size: str) -> str:
    if path:
        return f"""      path: {path}"""
    return f"""      match:
        size: {fallback_size}"""


def _grub_device_line(enabled: bool) -> str:
    return f'      grub_device: {str(enabled).lower()}'


def emit_single_disk_yaml(
    split_docker: bool = True,
    os_disk_path: str | None = None,
    uefi_boot: bool = False,
) -> str:
    return f"""
storage:
  swap:
    size: 0
  config:
    - type: disk
      id: os-disk
{_disk_locator_yaml(os_disk_path, 'smallest')}
      ptable: gpt
      wipe: superblock-recursive
      preserve: false
{_grub_device_line(not uefi_boot)}
    - type: partition
      id: bios-boot
      device: os-disk
      size: 1048576
      flag: bios_grub
    - type: partition
      id: efi-partition
      device: os-disk
      size: 550M
      flag: boot
{_grub_device_line(uefi_boot)}
    - type: format
      id: efi-format
      volume: efi-partition
      fstype: fat32
    - type: mount
      id: efi-mount
      path: /boot/efi
      device: efi-format
{_single_disk_tail(split_docker)}
""".strip()


def emit_two_disk_yaml(
    os_disk_path: str | None = None,
    data_disk_path: str | None = None,
    uefi_boot: bool = False,
) -> str:
    return f"""
storage:
  swap:
    size: 0
  config:
    - type: disk
      id: os-disk
{_disk_locator_yaml(os_disk_path, 'smallest')}
      ptable: gpt
      wipe: superblock-recursive
      preserve: false
{_grub_device_line(not uefi_boot)}
    - type: partition
      id: bios-boot
      device: os-disk
      size: 1048576
      flag: bios_grub
    - type: partition
      id: efi-partition
      device: os-disk
      size: 550M
      flag: boot
{_grub_device_line(uefi_boot)}
    - type: format
      id: efi-format
      volume: efi-partition
      fstype: fat32
    - type: mount
      id: efi-mount
      path: /boot/efi
      device: efi-format
    - type: partition
      id: root-partition
      device: os-disk
      size: -1
    - type: format
      id: root-format
      volume: root-partition
      fstype: ext4
    - type: mount
      id: root-mount
      path: /
      device: root-format
    - type: disk
      id: data-disk
{_disk_locator_yaml(data_disk_path, 'largest')}
      ptable: gpt
      wipe: superblock-recursive
      preserve: false
    - type: partition
      id: docker-partition
      device: data-disk
      size: -1
    - type: format
      id: docker-format
      volume: docker-partition
      fstype: xfs
    - type: mount
      id: docker-mount
      path: /var/lib/docker
      device: docker-format
      options: defaults,prjquota
""".strip()


def emit_storage_yaml(mode: str) -> str:
    if mode == 'auto':
        disks = _lsblk_disks()
        uefi_boot = _is_uefi_boot()
        if len(disks) == 1:
            return emit_single_disk_yaml(
                split_docker=disks[0].size_bytes >= SINGLE_DISK_SPLIT_MIN_BYTES,
                os_disk_path=disks[0].path,
                uefi_boot=uefi_boot,
            )
        if len(disks) >= 2:
            return emit_two_disk_yaml(
                os_disk_path=disks[0].path,
                data_disk_path=disks[-1].path,
                uefi_boot=uefi_boot,
            )
        raise RuntimeError(
            'ambiguous storage layout: no installable disks found'
        )
    if mode == 'single-disk':
        return emit_single_disk_yaml()
    if mode == 'two-disk':
        return emit_two_disk_yaml()
    raise ValueError(f'unsupported mode: {mode}')


def rewrite_autoinstall(path: Path, mode: str) -> None:
    path.write_text(emit_storage_yaml(mode) + '\n')


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=['single-disk', 'two-disk', 'auto'], default='auto')
    parser.add_argument('--rewrite-autoinstall', type=Path)
    args = parser.parse_args()

    try:
        if args.rewrite_autoinstall:
            rewrite_autoinstall(args.rewrite_autoinstall, args.mode)
        else:
            print(emit_storage_yaml(args.mode))
    except Exception as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
