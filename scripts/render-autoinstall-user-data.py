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


def build_autoinstall_yaml(mode: str, hostname: str, username: str, password_hash: str) -> str:
    storage_yaml = run_storage_generator(mode).rstrip()
    indented_storage_yaml = '\n'.join(
        ('  ' + line) if line.strip() else line
        for line in storage_yaml.splitlines()
    )
    return f'''#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: {hostname}
    username: {username}
    password: "{password_hash}"
  ssh:
    install-server: true
    allow-pw: true
  user-data:
    disable_root: true
    users:
      - default
      - name: {username}
        gecos: Vast Bootstrap
        passwd: "{password_hash}"
        lock_passwd: false
        shell: /bin/bash
        groups: [adm, sudo]
        sudo: ALL=(ALL) NOPASSWD:ALL
{indented_storage_yaml}
{render_late_commands()}'''


def render_early_commands(mode: str) -> str:
    if mode != 'auto':
        return ''

    return '''  early-commands:
    - ['cp', '/cdrom/opt-vast-host-installer-overlay/autoinstall-auto.yaml', '/autoinstall.yaml']
'''


def render_late_commands() -> str:
    return '''  late-commands:
    - ['mkdir', '-p', '/target/opt/vast-host-installer']
    - ['tar', '-xzf', '/cdrom/opt-vast-host-installer-overlay/vast-host-installer-payload.tgz', '-C', '/target/opt/vast-host-installer']
    - ['cp', '/target/opt/vast-host-installer/systemd/vast-host-installer-first-run-notice.service', '/target/etc/systemd/system/vast-host-installer-first-run-notice.service']
    - ['curtin', 'in-target', '--target=/target', '--', 'chmod', '+x', '/opt/vast-host-installer/bin/vast-host-installer']
    - ['curtin', 'in-target', '--target=/target', '--', 'systemctl', 'enable', 'vast-host-installer-first-run-notice.service']
'''


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

    password_hash = args.password_hash
    if not password_hash:
        if args.password:
            password_hash = sha512_crypt_fallback(args.password)
        else:
            password_hash = 'REPLACE_ME_WITH_A_REAL_HASH'

    rendered = build_autoinstall_yaml(args.mode, args.hostname, args.username, password_hash)
    if args.mode == 'auto':
        rendered = rendered.replace('  ssh:\n    install-server: true\n    allow-pw: true\n', '  ssh:\n    install-server: true\n    allow-pw: true\n' + render_early_commands(args.mode), 1)
    sys.stdout.write(rendered)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
