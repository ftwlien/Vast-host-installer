#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_DIR="$ROOT_DIR/iso"
BUILD_DIR="$ISO_DIR/build"
WORK_DIR="$BUILD_DIR/work"
EXTRACT_DIR="$WORK_DIR/extracted"
OUTPUT_ISO="$BUILD_DIR/vast-host-installer-jammy-custom.iso"
UPSTREAM_ISO="${1:-}"

if [[ -z "$UPSTREAM_ISO" ]]; then
  echo "Usage: $0 /path/to/ubuntu.iso"
  exit 1
fi

if [[ ! -f "$UPSTREAM_ISO" ]]; then
  echo "Upstream ISO not found: $UPSTREAM_ISO"
  exit 2
fi

for cmd in xorriso rsync; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd"
    echo "Install it first, for example: sudo apt-get install -y xorriso rsync"
    exit 3
  fi
done

mkdir -p "$BUILD_DIR" "$WORK_DIR" "$EXTRACT_DIR"
if [[ -d "$EXTRACT_DIR" ]]; then
  chmod -R u+w "$EXTRACT_DIR" 2>/dev/null || true
  find "$EXTRACT_DIR" -type d -exec chmod u+w {} + 2>/dev/null || true
fi
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
rm -f "$OUTPUT_ISO"

xorriso -osirrox on -indev "$UPSTREAM_ISO" -extract / "$EXTRACT_DIR" >/dev/null 2>&1
chmod -R u+w "$EXTRACT_DIR" 2>/dev/null || true
find "$EXTRACT_DIR" -type d -exec chmod u+w {} + 2>/dev/null || true

mkdir -p "$EXTRACT_DIR/nocloud"
rsync -a "$ISO_DIR/nocloud/" "$EXTRACT_DIR/nocloud/"
rsync -a "$ISO_DIR/overlay/" "$EXTRACT_DIR/opt-vast-host-installer-overlay/"
"$ROOT_DIR/scripts/patch-iso-autoinstall-boot.sh" "$EXTRACT_DIR"

if [[ ! -f "$EXTRACT_DIR/boot/grub/grub.cfg" ]]; then
  echo "Expected boot file missing after extraction: $EXTRACT_DIR/boot/grub/grub.cfg"
  echo "Refusing to attempt ISO rebuild blindly."
  exit 4
fi

xorriso -as mkisofs \
  -r \
  -V 'VASTHOST_JAMMY' \
  -o "$OUTPUT_ISO" \
  -J -l \
  "$EXTRACT_DIR" >/dev/null 2>&1

cat > "$BUILD_DIR/CUSTOM-ISO-PLAN.txt" <<EOF
Custom ISO rebuild attempt complete.

Upstream ISO:
$UPSTREAM_ISO

Extracted tree:
$EXTRACT_DIR

Injected paths:
- $EXTRACT_DIR/nocloud/
- $EXTRACT_DIR/opt-vast-host-installer-overlay/

Output ISO:
$OUTPUT_ISO

Important:
- this is the first rebuild pass, not yet a fully validated production remaster pipeline
- Jammy GRUB patching was attempted before rebuild
- payload handoff is currently via autoinstall late-commands
EOF

echo "Prepared extracted ISO tree in $EXTRACT_DIR"
echo "Built custom ISO candidate at $OUTPUT_ISO"
echo "Plan/status written to $BUILD_DIR/CUSTOM-ISO-PLAN.txt"
