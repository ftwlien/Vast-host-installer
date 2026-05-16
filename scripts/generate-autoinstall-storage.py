#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
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
        ['lsblk', '-b', '-J', '-o', 'PATH,SIZE,TYPE,RM,TRAN,MOUNTPOINTS'],
        text=True,
    )
    return _parse_lsblk_disks(output)


def _lsblk_tree() -> list[dict]:
    output = subprocess.check_output(
        ['lsblk', '-b', '-J', '-o', 'PATH,SIZE,TYPE,RM,TRAN,MOUNTPOINTS'],
        text=True,
    )
    return json.loads(output).get('blockdevices') or []


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
        if device.get('rm') is True or str(device.get('tran') or '').lower() == 'usb':
            continue
        if _has_install_media_mount(device):
            continue
        disks.append(Disk(path=str(device['path']), size_bytes=int(device['size'])))
    return sorted(disks, key=lambda disk: (disk.size_bytes, disk.path))


def _select_target_disks(disks: list[Disk]) -> list[Disk]:
    if disks:
        return disks
    raise RuntimeError('ambiguous storage layout: no installable disks found')


def _find_device(tree: list[dict], path: str) -> dict | None:
    for device in tree:
        if device.get('path') == path:
            return device
        found = _find_device(device.get('children') or [], path)
        if found:
            return found
    return None


def _child_partitions(device: dict) -> list[str]:
    partitions: list[str] = []
    for child in device.get('children') or []:
        if child.get('type') == 'part':
            partitions.append(str(child['path']))
        partitions.extend(_child_partitions(child))
    return partitions


def _realpath(path: str) -> str:
    try:
        return os.path.realpath(path)
    except Exception:
        return path


def _run_quiet(command: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def _mounted_sources() -> list[tuple[str, str]]:
    result = _run_quiet(['findmnt', '-rn', '-o', 'SOURCE,TARGET'])
    if result.returncode != 0:
        raise RuntimeError(f'findmnt failed: {result.stderr.strip()}')
    mounts: list[tuple[str, str]] = []
    for line in result.stdout.splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) == 2:
            mounts.append((parts[0], parts[1]))
    return mounts


def _target_partition_paths(target_disks: list[Disk]) -> set[str]:
    tree = _lsblk_tree()
    partitions: set[str] = set()
    for disk in target_disks:
        device = _find_device(tree, disk.path)
        if not device:
            continue
        partitions.update(_realpath(path) for path in _child_partitions(device))
    return partitions


def _is_protected_mount(target: str) -> bool:
    protected = ('/', '/cdrom', '/run/live', '/rofs')
    return target in protected or target.startswith('/cdrom/') or target.startswith('/run/live/')


def prepare_target_disks() -> None:
    target_disks = _select_target_disks(_lsblk_disks())
    target_partitions = _target_partition_paths(target_disks)
    if not target_partitions:
        return

    swap_result = _run_quiet(['swapon', '--show=NAME', '--noheadings'])
    if swap_result.returncode == 0:
        for swap_path in swap_result.stdout.splitlines():
            if _realpath(swap_path.strip()) in target_partitions:
                _run_quiet(['swapoff', swap_path.strip()])

    target_mounts = [
        (source, target)
        for source, target in _mounted_sources()
        if _realpath(source) in target_partitions
    ]
    if any(target == '/var/log' for _, target in target_mounts):
        _run_quiet(['systemctl', 'stop', 'rsyslog.service'])
        _run_quiet(['systemctl', 'stop', 'syslog.socket'])

    for source, target in sorted(target_mounts, key=lambda item: len(item[1]), reverse=True):
        if _is_protected_mount(target):
            raise RuntimeError(
                f'refusing to unmount protected live mount {target} from target disk source {source}'
            )
        result = _run_quiet(['umount', target])
        if result.returncode != 0 and target == '/var/log':
            result = _run_quiet(['umount', '-l', target])
        if result.returncode != 0:
            raise RuntimeError(
                f'failed to unmount target disk source {source} from {target}: {result.stderr.strip()}'
            )

    remaining = [
        (source, target)
        for source, target in _mounted_sources()
        if _realpath(source) in target_partitions and not _is_protected_mount(target)
    ]
    if remaining:
        details = ', '.join(f'{source} on {target}' for source, target in remaining)
        raise RuntimeError(f'target disk partitions are still mounted after cleanup: {details}')


def detect_mode() -> str:
    disks = _lsblk_disks()
    if len(disks) == 1:
        return 'single-disk'
    if len(disks) == 2:
        return 'two-disk'
    if len(disks) >= 3:
        return 'smallest-os-raid0'
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


def emit_smallest_os_raid0_yaml(
    os_disk_path: str | None = None,
    data_disk_paths: list[str] | None = None,
    uefi_boot: bool = False,
) -> str:
    data_disk_paths = data_disk_paths or []
    data_disk_blocks: list[str] = []
    data_partition_ids: list[str] = []
    for idx, path in enumerate(data_disk_paths):
        disk_id = f'data-disk-{idx}'
        part_id = f'data-partition-{idx}'
        data_partition_ids.append(part_id)
        data_disk_blocks.append(f"""
    - type: disk
      id: {disk_id}
{_disk_locator_yaml(path, 'largest')}
      ptable: gpt
      wipe: superblock-recursive
      preserve: false
    - type: partition
      id: {part_id}
      device: {disk_id}
      size: -1
""".rstrip())

    if len(data_partition_ids) == 0:
        data_tail = ''
    elif len(data_partition_ids) == 1:
        data_tail = f"""
    - type: format
      id: docker-format
      volume: {data_partition_ids[0]}
      fstype: xfs
    - type: mount
      id: docker-mount
      path: /var/lib/docker
      device: docker-format
      options: defaults,prjquota
""".rstrip()
    else:
        devices_yaml = '[' + ', '.join(data_partition_ids) + ']'
        data_tail = f"""
    - type: raid
      id: docker-raid0
      name: md0
      raidlevel: 0
      devices: {devices_yaml}
      preserve: false
    - type: format
      id: docker-format
      volume: docker-raid0
      fstype: xfs
    - type: mount
      id: docker-mount
      path: /var/lib/docker
      device: docker-format
      options: defaults,nofail,prjquota
""".rstrip()

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
{chr(10).join(data_disk_blocks)}
{data_tail}
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
        if len(disks) == 2:
            return emit_two_disk_yaml(
                os_disk_path=disks[0].path,
                data_disk_path=disks[-1].path,
                uefi_boot=uefi_boot,
            )
        if len(disks) >= 3:
            return emit_smallest_os_raid0_yaml(
                os_disk_path=disks[0].path,
                data_disk_paths=[disk.path for disk in disks[1:]],
                uefi_boot=uefi_boot,
            )
        raise RuntimeError(
            'ambiguous storage layout: no installable disks found'
        )
    if mode == 'single-disk':
        return emit_single_disk_yaml()
    if mode == 'two-disk':
        return emit_two_disk_yaml()
    if mode == 'smallest-os-raid0':
        return emit_smallest_os_raid0_yaml(data_disk_paths=[None, None])
    raise ValueError(f'unsupported mode: {mode}')


def rewrite_autoinstall(path: Path, mode: str) -> None:
    path.write_text(emit_storage_yaml(mode) + '\n')


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=['single-disk', 'two-disk', 'smallest-os-raid0', 'auto'], default='auto')
    parser.add_argument('--rewrite-autoinstall', type=Path)
    parser.add_argument('--prepare-target-disks', action='store_true')
    args = parser.parse_args()

    try:
        if args.prepare_target_disks:
            prepare_target_disks()
            if not args.rewrite_autoinstall:
                return 0
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
