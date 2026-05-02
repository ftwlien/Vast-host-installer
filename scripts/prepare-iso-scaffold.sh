#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_DIR="$ROOT_DIR/iso"
NOCLOUD_DIR="$ISO_DIR/nocloud"
OVERLAY_DIR="$ISO_DIR/overlay"
BUILD_DIR="$ISO_DIR/build"

mkdir -p "$NOCLOUD_DIR" "$OVERLAY_DIR" "$BUILD_DIR"

PAYLOAD="$($ROOT_DIR/scripts/build-installer-payload.sh)"
python3 "$ROOT_DIR/scripts/render-autoinstall-user-data.py" --mode auto --hostname vast-bootstrap --username vastbootstrap > "$NOCLOUD_DIR/user-data"
printf 'instance-id: vast-host-installer\nlocal-hostname: vast-bootstrap\n' > "$NOCLOUD_DIR/meta-data"
cp "$PAYLOAD" "$OVERLAY_DIR/vast-host-installer-payload.tgz"

cat > "$BUILD_DIR/README.txt" <<EOF
ISO scaffold prepared.

Files staged:
- $NOCLOUD_DIR/user-data
- $NOCLOUD_DIR/meta-data
- $OVERLAY_DIR/vast-host-installer-payload.tgz

Next step: integrate these into a real Ubuntu custom ISO build flow.
EOF

echo "Prepared ISO scaffold in $ISO_DIR"
