#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_PATH="$ROOT_DIR/iso/build/vast-host-installer-jammy-custom.iso"
RELEASE_TAG="${1:-v0.1.5}"

overall="OK"

mark_warn() {
  overall="WARN"
}

print_kv() {
  printf '%-18s %s\n' "$1:" "$2"
}

human_size() {
  local path="$1"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "$(stat -c '%s' "$path")"
  else
    stat -c '%s bytes' "$path"
  fi
}

echo "Vast Host Installer Health"
echo "=========================="
print_kv "Workspace" "$ROOT_DIR"
print_kv "Time" "$(date -Is)"
echo

echo "Machine"
echo "-------"
print_kv "Uptime" "$(uptime -p 2>/dev/null || uptime)"
print_kv "Load" "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo unknown)"
print_kv "Disk free" "$(df -h "$ROOT_DIR" | awk 'NR==2 {print $4 " free on " $6}')"
print_kv "Memory" "$(free -h | awk '/^Mem:/ {print $7 " available / " $2 " total"}')"
echo

echo "Active Jobs"
echo "-----------"
jobs_found="$(pgrep -af 'gh release|xorriso|build-custom-iso|prepare-iso-scaffold|rsync' 2>/dev/null | grep -v 'health-check.sh' || true)"
if [[ -n "$jobs_found" ]]; then
  mark_warn
  echo "$jobs_found"
else
  echo "No ISO build/upload jobs running."
fi
echo

echo "Git"
echo "---"
cd "$ROOT_DIR" || exit 1
print_kv "Branch" "$(git branch --show-current 2>/dev/null || echo unknown)"
print_kv "Commit" "$(git log -1 --oneline 2>/dev/null || echo unknown)"
dirty="$(git status --short 2>/dev/null || true)"
if [[ -n "$dirty" ]]; then
  mark_warn
  echo "Worktree has uncommitted changes:"
  echo "$dirty"
else
  echo "Worktree clean."
fi
echo

echo "Local ISO"
echo "---------"
if [[ -f "$ISO_PATH" ]]; then
  print_kv "Path" "$ISO_PATH"
  print_kv "Size" "$(human_size "$ISO_PATH")"
  print_kv "Changed" "$(stat -c '%y' "$ISO_PATH" | cut -d'.' -f1)"
  if command -v sha256sum >/dev/null 2>&1; then
    print_kv "SHA256" "$(sha256sum "$ISO_PATH" | awk '{print $1}')"
  fi
else
  mark_warn
  echo "Missing local ISO: $ISO_PATH"
fi
echo

echo "GitHub"
echo "------"
if ! command -v gh >/dev/null 2>&1; then
  mark_warn
  echo "gh is not installed."
elif ! timeout 15 gh auth status >/tmp/vast-health-gh-auth.$$ 2>&1; then
  mark_warn
  echo "gh auth is not healthy:"
  sed 's/^/  /' /tmp/vast-health-gh-auth.$$
  rm -f /tmp/vast-health-gh-auth.$$
else
  rm -f /tmp/vast-health-gh-auth.$$
  echo "gh auth OK."
  release_json="$(timeout 30 gh release view "$RELEASE_TAG" --json tagName,url,assets 2>/tmp/vast-health-gh-release.$$ || true)"
  if [[ -z "$release_json" ]]; then
    mark_warn
    echo "Could not read release $RELEASE_TAG:"
    sed 's/^/  /' /tmp/vast-health-gh-release.$$
  else
    python3 - "$release_json" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
assets = data.get("assets", [])
iso = next((asset for asset in assets if asset.get("name", "").endswith(".iso")), None)
print(f"Release: {data.get('tagName')} {data.get('url')}")
if iso:
    size_gib = iso.get("size", 0) / (1024 ** 3)
    print(f"ISO asset: {iso.get('name')} ({size_gib:.2f} GiB)")
    print(f"Download: {iso.get('url')}")
else:
    print("ISO asset: missing")
    sys.exit(2)
PY
    if [[ $? -ne 0 ]]; then
      mark_warn
    fi
  fi
  rm -f /tmp/vast-health-gh-release.$$
fi
echo

echo "Answer"
echo "------"
if [[ "$overall" == "OK" ]]; then
  echo "OK: no active build/upload jobs, local ISO exists, GitHub release is reachable."
else
  echo "WARN: read the section above with details."
fi
