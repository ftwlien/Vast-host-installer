#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

MARKER_BEGIN = '# VAST_STORAGE_POLICY_BEGIN'
MARKER_END = '# VAST_STORAGE_POLICY_END'


@dataclass(frozen=True)
class Disk:
    path: str
    size_bytes: int


def _lsblk_disks() -> list[Disk]:
    output = subprocess.check_output(
        ['lsblk', '-b', '-dn', '-o', 'PATH,SIZE,TYPE'],
        text=True,
    )
    disks: list[Disk] = []
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 3:
            raise RuntimeError(f'unexpected lsblk output line: {raw_line!r}')
        path, size_str, dev_type = parts
        if dev_type != 'disk':
            continue
        disks.append(Disk(path=path, size_bytes=int(size_str)))
    return sorted(disks, key=lambda disk: (disk.size_bytes, disk.path))


def detect_mode() -> str:
    disks = _lsblk_disks()
    if len(disks) == 1:
        return 'single-disk'
    if len(disks) == 2:
        if disks[0].size_bytes == disks[1].size_bytes:
            raise RuntimeError(
                'ambiguous storage layout: exactly two disks were found, but they are the same size'
            )
        return 'two-disk'
    raise RuntimeError(
        f'ambiguous storage layout: expected exactly 1 or 2 disks, found {len(disks)}'
    )


def emit_single_disk_yaml() -> str:
    return """
storage:
  swap:
    size: 0
  config:
    - type: disk
      id: os-disk
      match:
        size: smallest
      ptable: gpt
      wipe: superblock-recursive
      preserve: false
      grub_device: true
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
      grub_device: true
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
""".strip()


def emit_two_disk_yaml() -> str:
    return """
storage:
  swap:
    size: 0
  config:
    - type: disk
      id: os-disk
      match:
        size: smallest
      ptable: gpt
      wipe: superblock-recursive
      preserve: false
      grub_device: true
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
      grub_device: true
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
      match:
        size: largest
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
""".strip()


def emit_storage_yaml(mode: str) -> str:
    if mode == 'auto':
        mode = detect_mode()
    if mode == 'single-disk':
        return emit_single_disk_yaml()
    if mode == 'two-disk':
        return emit_two_disk_yaml()
    raise ValueError(f'unsupported mode: {mode}')


def rewrite_autoinstall(path: Path, mode: str) -> None:
    replacement = emit_storage_yaml(mode)
    text = path.read_text()
    pattern = re.compile(
        rf'(?ms)^([ \t]*){re.escape(MARKER_BEGIN)}\n.*?^\1{re.escape(MARKER_END)}$'
    )
    match = pattern.search(text)
    if not match:
        raise RuntimeError(
            f'could not find storage policy markers {MARKER_BEGIN!r} .. {MARKER_END!r} in {path}'
        )
    indent = match.group(1)
    indented_replacement = '\n'.join(
        f'{indent}{line}' if line else line
        for line in replacement.splitlines()
    )
    new_block = f'{indent}{MARKER_BEGIN}\n{indented_replacement}\n{indent}{MARKER_END}'
    path.write_text(pattern.sub(new_block, text, count=1))


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
