#!/bin/sh

case "$-" in
  *i*) ;;
  *) return 0 2>/dev/null || exit 0 ;;
esac

[ -t 1 ] || return 0 2>/dev/null || exit 0
[ ! -f /var/lib/vast-host-installer/setup-complete ] || return 0 2>/dev/null || exit 0
[ -x /opt/vast-host-installer/bin/vast-host-installer ] || return 0 2>/dev/null || exit 0

purple=''
reset=''
bold=''
if [ -t 1 ]; then
  purple="$(printf '\033[1;38;5;93m')"
  reset="$(printf '\033[0m')"
  bold="$(printf '\033[1m')"
fi

printf '%s%s' "$purple" "$bold"
cat <<'EOF'

██╗   ██╗ █████╗ ███████╗████████╗     █████╗ ██╗
██║   ██║██╔══██╗██╔════╝╚══██╔══╝    ██╔══██╗██║
██║   ██║███████║███████╗   ██║       ███████║██║
╚██╗ ██╔╝██╔══██║╚════██║   ██║       ██╔══██║██║
 ╚████╔╝ ██║  ██║███████║   ██║       ██║  ██║██║
  ╚═══╝  ╚═╝  ╚═╝╚══════╝   ╚═╝       ╚═╝  ╚═╝╚═╝
EOF
printf '%s' "$reset"
cat <<'EOF'

 VAST AI Host Installer is ready.
 ----------------------------------------------------------------
 Ubuntu is installed and the Vast bootstrap tools are on this host.

 Run this command to continue setup:

   sudo /opt/vast-host-installer/bin/vast-host-installer --first-run
 ----------------------------------------------------------------

EOF
