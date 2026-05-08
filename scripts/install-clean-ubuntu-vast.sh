#!/usr/bin/env bash
set -euo pipefail

# Official-Ubuntu bootstrapper.
# Stages the same installer used by the ISO, then launches the same first-run UI
# with one extra safety mode: --official-ubuntu storage wizard.

REPO_URL="${VAST_HOST_INSTALLER_REPO_URL:-https://github.com/ftwlien/Vast-host-installer.git}"
REPO_VERSION="${VAST_HOST_INSTALLER_REPO_VERSION:-main}"
INSTALL_ROOT="${VAST_HOST_INSTALLER_PATH:-/opt/vast-host-installer}"
STAGE_ONLY=0
EXTRA_ARGS=()

info() { printf '==> %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/install-clean-ubuntu-vast.sh [options]

Stages /opt/vast-host-installer on an already-installed official Ubuntu host,
then launches the same ISO first-run installer flow:

  sudo /opt/vast-host-installer/bin/vast-host-installer --first-run --official-ubuntu

The --official-ubuntu flag only changes storage safety:
  - adds a storage wizard before Phase 1
  - requires a separate Docker/Vast storage partition or data disk
  - never live-repartitions the mounted root disk
  - can use an already prepared non-root partition for /var/lib/docker
  - can wipe a clear non-root 2nd disk only after typed confirmation

For 1-disk production hosts, create this during Ubuntu install:
  EFI:              1G
  /:                100G ext4
  /var/lib/docker:  rest of disk as separate partition

After that, the flow is the same as the ISO:
  Phase 1 -> reboot -> --resume
  Phase 2 NVIDIA -> reboot -> --preflight-phase3
  Phase 3 -> --resume

Options:
  --stage-only       Install/update /opt/vast-host-installer, then print command
  --repo-url URL     Override source repo
  --repo-version REF Override branch/tag/commit, default: main
  -h, --help         Show help

Any unknown args are passed through to vast-host-installer.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage-only) STAGE_ONLY=1; shift ;;
    --repo-url) REPO_URL="${2:-}"; shift 2 ;;
    --repo-version) REPO_VERSION="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) EXTRA_ARGS+=("$1"); shift ;;
  esac
done

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo -E "$0" "$@"
fi

[[ -r /etc/os-release ]] || die "Cannot read /etc/os-release"
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "This installer supports Ubuntu only. Detected: ${PRETTY_NAME:-unknown}"

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

info "Installing bootstrap dependencies"
apt-get update
apt-get install -y git ca-certificates curl sudo

info "Installing/updating Vast Host Installer source at $INSTALL_ROOT"
if [[ -d "$INSTALL_ROOT/.git" ]]; then
  git -C "$INSTALL_ROOT" fetch --all --tags
  git -C "$INSTALL_ROOT" checkout "$REPO_VERSION"
  git -C "$INSTALL_ROOT" pull --ff-only || true
else
  rm -rf "$INSTALL_ROOT"
  git clone --branch "$REPO_VERSION" "$REPO_URL" "$INSTALL_ROOT"
fi

install -d -m 0755 /usr/local/bin
cat >/usr/local/bin/vast-host-installer-source <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$INSTALL_ROOT"
exec bash install/main.sh "\$@"
EOF
chmod 0755 /usr/local/bin/vast-host-installer-source

cmd=("$INSTALL_ROOT/bin/vast-host-installer" --first-run --official-ubuntu "${EXTRA_ARGS[@]}")

cat <<EOF

Vast Host Installer is staged.

Run/continuation command:
  sudo /opt/vast-host-installer/bin/vast-host-installer --first-run --official-ubuntu

This uses the same ISO installer screens/phases, with the official-Ubuntu storage wizard added before Phase 1.
EOF

if [[ "$STAGE_ONLY" -eq 1 ]]; then
  exit 0
fi

exec "${cmd[@]}"
