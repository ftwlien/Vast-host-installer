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
  purple="$(printf '\033[1;38;5;201m')"
  reset="$(printf '\033[0m')"
  bold="$(printf '\033[1m')"
fi

resume_cmd='sudo /opt/vast-host-installer/bin/vast-host-installer --first-run'
resume_text='Run this command to continue setup:'
if [ -f /var/lib/vast-host-installer/resume.env ]; then
  resume_cmd='sudo /opt/vast-host-installer/bin/vast-host-installer --resume'
  resume_text='Setup is waiting for manual resume. Run this command:'
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

EOF
printf ' %s\n\n' "$resume_text"
printf '   %s\n' "$resume_cmd"
cat <<'EOF'

 ----------------------------------------------------------------

EOF
