#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import shlex
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORAGE_GEN = ROOT / 'scripts' / 'generate-autoinstall-storage.py'


def run_storage_generator(mode: str) -> str:
    return subprocess.check_output([
        'python3', str(STORAGE_GEN), '--mode', mode
    ], text=True)


def direct_storage_yaml() -> str:
    return '''storage:
  layout:
    name: direct'''


def build_autoinstall_yaml(
    mode: str,
    hostname: str,
    username: str,
    password_hash: str,
    include_runtime_early_commands: bool,
) -> str:
    if mode == 'auto' and include_runtime_early_commands:
        storage_yaml = direct_storage_yaml()
    else:
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
{render_early_commands(mode, hostname, username, password_hash, include_runtime_early_commands)}
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


def render_early_commands(
    mode: str,
    hostname: str,
    username: str,
    password_hash: str,
    include_runtime_early_commands: bool,
) -> str:
    if mode != 'auto' or not include_runtime_early_commands:
        return ''

    command = ' '.join([
        'python3',
        '/cdrom/opt-vast-host-installer-overlay/scripts/render-autoinstall-user-data.py',
        '--mode', 'auto',
        '--hostname', shlex.quote(hostname),
        '--username', shlex.quote(username),
        '--password-hash', shlex.quote(password_hash),
        '--no-runtime-early-commands',
        '>', '/autoinstall.yaml',
    ])
    return f'''  early-commands:
    - ['bash', '-lc', {command!r}]
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
    parser.add_argument('--no-runtime-early-commands', action='store_true')
    args = parser.parse_args()

    password_hash = args.password_hash
    if not password_hash:
        if args.password:
            password_hash = sha512_crypt_fallback(args.password)
        else:
            password_hash = 'REPLACE_ME_WITH_A_REAL_HASH'

    rendered = build_autoinstall_yaml(
        args.mode,
        args.hostname,
        args.username,
        password_hash,
        include_runtime_early_commands=not args.no_runtime_early_commands,
    )
    sys.stdout.write(rendered)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
