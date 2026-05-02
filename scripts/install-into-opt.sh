#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DST_DIR="/opt/vast-host-installer"

sudo mkdir -p "$DST_DIR"
sudo rsync -a --delete "$SRC_DIR/" "$DST_DIR/"
sudo chmod +x "$DST_DIR/bin/vast-host-installer" || true

echo "Installed Vast Host Installer to $DST_DIR"
echo "Run first boot flow with: sudo $DST_DIR/bin/vast-host-installer --first-run"
