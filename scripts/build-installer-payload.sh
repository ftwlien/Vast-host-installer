#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/build"
PAYLOAD="$OUT_DIR/vast-host-installer-payload.tgz"

mkdir -p "$OUT_DIR"

tar \
  --exclude='build' \
  --exclude='__pycache__' \
  --exclude='.git' \
  -C "$ROOT_DIR" \
  -czf "$PAYLOAD" \
  README.md docs install web bin autoinstall systemd scripts

echo "$PAYLOAD"
