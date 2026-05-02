#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass


@dataclass
class Disk:
    path: str
    size: int


def list_disks() -> list[Disk]:
    payload = json.loads(subprocess.check_output([
        'lsblk', '-J', '-b', '-d', '-o', 'PATH,SIZE,TYPE'
    ], text=True))
    disks: list[Disk] = []
    for dev in payload.get('blockdevices', []):
        if dev.get('type') != 'disk':
            continue
        disks.append(Disk(path=dev.get('path', ''), size=int(dev.get('size') or 0)))
    return disks


def emit_single_disk_yaml(disk: Disk) -> str:
    return f"""
storage:
  config:
    - type: disk
      id: os-disk
      path: {disk.path}
      ptable: gpt
      wipe: superblock-recursive
      grub_device: true
    - type: partition
      id: os-disk-part
      device: os-disk
      size: -1
    - type: format
      id: os-format
      volume: os-disk-part
      fstype: ext4
    - type: mount
      id: os-mount
      device: os-format
      path: /
""".strip()


def emit_two_disk_yaml(os_disk: Disk) -> str:
    return f"""
storage:
  config:
    - type: disk
      id: os-disk
      path: {os_disk.path}
      ptable: gpt
      wipe: superblock-recursive
      grub_device: true
    - type: partition
      id: os-disk-part
      device: os-disk
      size: -1
    - type: format
      id: os-format
      volume: os-disk-part
      fstype: ext4
    - type: mount
      id: os-mount
      device: os-format
      path: /
""".strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=['single-disk', 'two-disk', 'auto'], default='auto')
    args = parser.parse_args()

    disks = sorted(list_disks(), key=lambda d: d.size)
    if not disks:
      print('No disks detected', file=sys.stderr)
      return 1

    if args.mode == 'single-disk':
        print(emit_single_disk_yaml(disks[0]))
        return 0

    if args.mode == 'two-disk':
        if len(disks) < 2:
            print('Need at least 2 disks for two-disk mode', file=sys.stderr)
            return 2
        print(emit_two_disk_yaml(disks[0]))
        return 0

    if len(disks) == 1:
        print(emit_single_disk_yaml(disks[0]))
        return 0
    if len(disks) == 2:
        print(emit_two_disk_yaml(disks[0]))
        return 0

    print('Ambiguous disk layout for autoinstall generation', file=sys.stderr)
    return 3


if __name__ == '__main__':
    raise SystemExit(main())
