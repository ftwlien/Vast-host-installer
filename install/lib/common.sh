#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[vast-host-installer] %s\n' "$*"
}

warn() {
  printf '[vast-host-installer][warn] %s\n' "$*" >&2
}

die() {
  printf '[vast-host-installer][error] %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

is_apt_system() {
  command -v apt-get >/dev/null 2>&1
}

ensure_basic_tools() {
  require_cmd bash
  require_cmd awk
  require_cmd sed
  require_cmd lsblk
  require_cmd findmnt
  require_cmd python3
}
