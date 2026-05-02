#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORAGE_GEN = ROOT / 'scripts' / 'generate-autoinstall-storage.py'


def run_storage_generator(mode: str) -> str:
    return subprocess.check_output([
        'python3', str(STORAGE_GEN), '--mode', mode
    ], text=True)


def sha512_crypt_fallback(password: str) -> str:
    salt = hashlib.sha256(password.encode()).hexdigest()[:16]
    try:
        import crypt
        return crypt.crypt(password, f'$6${salt}$')
    except Exception:
        raise RuntimeError('Unable to hash password automatically; generate a SHA-512 crypt hash manually.')


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=['single-disk', 'two-disk', 'auto'], default='auto')
    parser.add_argument('--hostname', default='vast-bootstrap')
    parser.add_argument('--username', default='vastbootstrap')
    parser.add_argument('--password-hash', default='')
    parser.add_argument('--password', default='')
    args = parser.parse_args()

    storage_yaml = run_storage_generator(args.mode).rstrip()

    password_hash = args.password_hash
    if not password_hash:
        if args.password:
            password_hash = sha512_crypt_fallback(args.password)
        else:
            password_hash = 'REPLACE_ME_WITH_A_REAL_HASH'

    indented_storage_yaml = '\n'.join(
        ('  ' + line) if line.strip() else line
        for line in storage_yaml.splitlines()
    )

    rendered = f'''#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: {args.hostname}
    username: {args.username}
    password: "{password_hash}"
  ssh:
    install-server: true
    allow-pw: true
  packages:
    - openssh-server
    - curl
    - git
    - python3
    - sudo
{indented_storage_yaml}
  late-commands:
    - curtin in-target --target=/target -- bash -lc 'mkdir -p /opt/vast-host-installer'
    - curtin in-target --target=/target -- bash -lc 'if [ -f /cdrom/opt-vast-host-installer-overlay/vast-host-installer-payload.tgz ]; then tar -xzf /cdrom/opt-vast-host-installer-overlay/vast-host-installer-payload.tgz -C /opt/vast-host-installer --strip-components=0; else echo "Missing payload tarball: /cdrom/opt-vast-host-installer-overlay/vast-host-installer-payload.tgz" > /opt/vast-host-installer/BOOTSTRAP-ERROR.txt; fi'
    - curtin in-target --target=/target -- bash -lc 'chmod +x /opt/vast-host-installer/bin/vast-host-installer || true'
    - curtin in-target --target=/target -- bash -lc 'echo "Run: sudo /opt/vast-host-installer/bin/vast-host-installer --first-run" > /etc/motd'
'''
    sys.stdout.write(rendered)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
