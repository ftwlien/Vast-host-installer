#!/usr/bin/env bash
set -euo pipefail

EXTRACT_DIR="${1:-}"
if [[ -z "$EXTRACT_DIR" ]]; then
  echo "Usage: $0 /path/to/extracted-iso-tree"
  exit 1
fi

if [[ ! -d "$EXTRACT_DIR" ]]; then
  echo "Extracted ISO tree not found: $EXTRACT_DIR"
  exit 2
fi

PATCHED=0
PATCH_REPORT="$EXTRACT_DIR/AUTOINSTALL-BOOT-PATCH-REPORT.txt"
: > "$PATCH_REPORT"

append_autoinstall_args() {
  local file="$1"
  if grep -q 'autoinstall ds=nocloud;s=/cdrom/nocloud/' "$file"; then
    echo "Already patched: $file" >> "$PATCH_REPORT"
    return 0
  fi

  python3 - "$file" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
original = text
needle = ' autoinstall ds=nocloud\\;s=/cdrom/nocloud/'

patterns = [
    r'^(\s*linux\s+.*?)(\s+---\s*)$',
    r'^(\s*linuxefi\s+.*?)(\s+---\s*)$',
]

for pattern in patterns:
    def repl(match):
        prefix = match.group(1)
        suffix = match.group(2)
        if 'autoinstall ds=nocloud\\;s=/cdrom/nocloud/' in prefix:
            return match.group(0)
        return f"{prefix}{needle}{suffix}"
    text = re.sub(pattern, repl, text, flags=re.MULTILINE)

if text == original:
    sys.exit(4)
path.write_text(text)
PY
  echo "Patched: $file" >> "$PATCH_REPORT"
}

for candidate in \
  "$EXTRACT_DIR/boot/grub/grub.cfg" \
  "$EXTRACT_DIR/boot/grub/loopback.cfg"
  do
  if [[ -f "$candidate" ]]; then
    append_autoinstall_args "$candidate"
    PATCHED=1
  fi
done

if [[ $PATCHED -eq 0 ]]; then
  echo "No supported Jammy GRUB config files found to patch." | tee -a "$PATCH_REPORT"
  echo "Expected one of:" | tee -a "$PATCH_REPORT"
  echo "- $EXTRACT_DIR/boot/grub/grub.cfg" | tee -a "$PATCH_REPORT"
  echo "- $EXTRACT_DIR/boot/grub/loopback.cfg" | tee -a "$PATCH_REPORT"
  exit 3
fi

echo "Boot patch report written to $PATCH_REPORT"
