#!/usr/bin/env bash
set -euo pipefail

EXTRACT_DIR="${1:-}"
if [[ -z "$EXTRACT_DIR" ]]; then
  echo "Usage: $0 /path/to/extracted-iso-tree" >&2
  exit 1
fi
if [[ ! -d "$EXTRACT_DIR" ]]; then
  echo "Extracted ISO tree not found: $EXTRACT_DIR" >&2
  exit 2
fi

for cmd in unmkinitramfs lsinitramfs cpio zstd python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required command: $cmd" >&2; exit 3; }
done

REPORT="$EXTRACT_DIR/CASPER-INITRD-NOISE-PATCH-REPORT.txt"
: > "$REPORT"

patch_one_initrd() {
  local initrd="$1" tmp out patched_count
  [[ -f "$initrd" ]] || return 0
  tmp="$(mktemp -d /tmp/casper-initrd-patch.XXXXXX)"
  out="${initrd}.patched"
  unmkinitramfs "$initrd" "$tmp" >/dev/null

  patched_count="$({
    find "$tmp" -path '*/scripts/casper-helpers' -type f -print0 | while IFS= read -r -d '' helper; do
      python3 - "$helper" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
old = 'eval $(fstype < $1)'
new = 'eval $(fstype < $1 2>/dev/null)'
if old in text:
    path.write_text(text.replace(old, new, 1))
    print(path)
PY
    done
  } | wc -l | tr -d ' ')"

  if [[ "$patched_count" -lt 1 ]]; then
    rm -rf "$tmp"
    echo "No casper-helpers fstype probe patched in $initrd" >&2
    exit 4
  fi

  rm -f "$out"
  if [[ -d "$tmp/early" ]]; then
    (cd "$tmp/early" && find . -print0 | cpio --null -o --format=newc --quiet) > "$out"
  else
    : > "$out"
  fi
  if [[ -d "$tmp/early2" ]]; then
    (cd "$tmp/early2" && find . -print0 | cpio --null -o --format=newc --quiet) >> "$out"
  fi
  (cd "$tmp/main" && find . -print0 | cpio --null -o --format=newc --quiet | zstd -19 -T0 -q) >> "$out"

  if ! lsinitramfs "$out" > "$tmp/lsinitramfs.txt"; then
    rm -rf "$tmp" "$out"
    echo "Repacked initrd failed listing validation: $initrd" >&2
    exit 5
  fi
  grep -q '^scripts/casper-helpers$' "$tmp/lsinitramfs.txt" || {
    rm -rf "$tmp" "$out"
    echo "Repacked initrd failed casper-helpers validation: $initrd" >&2
    exit 5
  }
  mv "$out" "$initrd"
  rm -rf "$tmp"
  echo "Patched $initrd ($patched_count casper-helpers file(s))" >> "$REPORT"
}

patch_one_initrd "$EXTRACT_DIR/casper/initrd"
patch_one_initrd "$EXTRACT_DIR/casper/hwe-initrd"

echo "Casper initrd noise patch report written to $REPORT"
