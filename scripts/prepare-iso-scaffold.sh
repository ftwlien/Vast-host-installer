#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_DIR="$ROOT_DIR/iso"
NOCLOUD_DIR="$ISO_DIR/nocloud"
OVERLAY_DIR="$ISO_DIR/overlay"
BUILD_DIR="$ISO_DIR/build"

mkdir -p "$NOCLOUD_DIR" "$OVERLAY_DIR" "$BUILD_DIR"

PASSWORD_HASH="${VAST_BOOTSTRAP_PASSWORD_HASH:-}"
PASSWORD_FILE="$ROOT_DIR/autoinstall/bootstrap-password.txt"
PASSWORD_HASH_FILE="$ROOT_DIR/autoinstall/bootstrap-password.hash"

if [[ -z "$PASSWORD_HASH" && -f "$PASSWORD_HASH_FILE" ]]; then
  PASSWORD_HASH="$(tr -d '\r\n' < "$PASSWORD_HASH_FILE")"
fi

if [[ -z "$PASSWORD_HASH" && -f "$PASSWORD_FILE" ]]; then
  PASSWORD="$(tr -d '\r\n' < "$PASSWORD_FILE")"
else
  PASSWORD="${VAST_BOOTSTRAP_PASSWORD:-}"
fi

if [[ -z "$PASSWORD_HASH" && -z "$PASSWORD" ]]; then
  echo "Missing bootstrap password input. Set VAST_BOOTSTRAP_PASSWORD or VAST_BOOTSTRAP_PASSWORD_HASH, or create one of:" >&2
  echo "- $PASSWORD_FILE (plain text password for local build only)" >&2
  echo "- $PASSWORD_HASH_FILE (SHA-512 crypt hash)" >&2
  exit 1
fi

PAYLOAD="$($ROOT_DIR/scripts/build-installer-payload.sh)"
RENDER_ARGS=(--mode auto --hostname vast-bootstrap --username vastbootstrap)
if [[ -n "$PASSWORD_HASH" ]]; then
  RENDER_ARGS+=(--password-hash "$PASSWORD_HASH")
else
  RENDER_ARGS+=(--password "$PASSWORD")
fi
python3 "$ROOT_DIR/scripts/render-autoinstall-user-data.py" "${RENDER_ARGS[@]}" > "$NOCLOUD_DIR/user-data"
printf 'instance-id: vast-host-installer\nlocal-hostname: vast-bootstrap\n' > "$NOCLOUD_DIR/meta-data"
mkdir -p "$OVERLAY_DIR/scripts"
cp "$PAYLOAD" "$OVERLAY_DIR/vast-host-installer-payload.tgz"
cp "$ROOT_DIR/scripts/generate-autoinstall-storage.py" "$OVERLAY_DIR/scripts/generate-autoinstall-storage.py"
chmod +x "$OVERLAY_DIR/scripts/generate-autoinstall-storage.py"

cat > "$BUILD_DIR/README.txt" <<EOF
ISO scaffold prepared.

Files staged:
- $NOCLOUD_DIR/user-data
- $NOCLOUD_DIR/meta-data
- $OVERLAY_DIR/vast-host-installer-payload.tgz

Next step: integrate these into a real Ubuntu custom ISO build flow.
EOF

echo "Prepared ISO scaffold in $ISO_DIR"
