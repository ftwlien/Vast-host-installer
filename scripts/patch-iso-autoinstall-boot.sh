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

patch_grub_defaults() {
  local file="$1"
  python3 - "$file" "$PATCH_REPORT" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
report_path = Path(sys.argv[2])
text = path.read_text()
original = text
report_lines = []

if re.search(r'^set timeout=\d+\s*$', text, flags=re.MULTILINE):
    text = re.sub(r'^set timeout=\d+\s*$', 'set timeout=3', text, count=1, flags=re.MULTILINE)
    report_lines.append(f"Patched timeout: {path}")
else:
    text = 'set timeout=3\n' + text
    report_lines.append(f"Inserted timeout: {path}")

hwe_entry_found = bool(re.search(r"menuentry ['\"]Ubuntu Server with the HWE kernel['\"]", text))
if hwe_entry_found:
    desired = 'set default="Ubuntu Server with the HWE kernel"'
    if re.search(r'^set default=.*$', text, flags=re.MULTILINE):
        text = re.sub(r'^set default=.*$', desired, text, count=1, flags=re.MULTILINE)
    else:
        timeout_match = re.search(r'^set timeout=.*$', text, flags=re.MULTILINE)
        if timeout_match:
            insert_at = timeout_match.end()
            text = text[:insert_at] + '\n' + desired + text[insert_at:]
        else:
            text = desired + '\n' + text
    report_lines.append(f"Set default to HWE entry: {path}")
else:
    report_lines.append(f"HWE entry not found; left default unchanged: {path}")

if text != original:
    path.write_text(text)

with report_path.open('a') as fh:
    for line in report_lines:
        fh.write(line + '\n')
PY
}

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
needle = ' autoinstall ds=nocloud\\;s=/cdrom/nocloud/ systemd.mask=var-log.mount'

patterns = [
    r'^(\s*linux\s+.*?)(\s+---\s*)$',
    r'^(\s*linuxefi\s+.*?)(\s+---\s*)$',
]

for pattern in patterns:
    def repl(match):
        prefix = match.group(1)
        suffix = match.group(2)
        if 'autoinstall ds=nocloud\\;s=/cdrom/nocloud/' in prefix:
            if 'systemd.mask=var-log.mount' not in prefix:
                return f"{prefix} systemd.mask=var-log.mount{suffix}"
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
    patch_grub_defaults "$candidate"
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
