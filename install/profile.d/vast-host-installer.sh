#!/bin/sh

case "$-" in
  *i*) ;;
  *) return 0 2>/dev/null || exit 0 ;;
esac

[ -t 1 ] || return 0 2>/dev/null || exit 0
[ ! -f /var/lib/vast-host-installer/setup-complete ] || return 0 2>/dev/null || exit 0
[ -x /opt/vast-host-installer/bin/vast-host-installer ] || return 0 2>/dev/null || exit 0

sky=''
reset=''
bold=''
if [ -t 1 ]; then
  sky="$(printf '\033[1;38;5;45m')"
  reset="$(printf '\033[0m')"
  bold="$(printf '\033[1m')"
fi

preflight_cmd=''
resume_cmd='sudo /opt/vast-host-installer/bin/vast-host-installer --first-run'
resume_text='Run this command to continue setup:'
if [ -f /var/lib/vast-host-installer/resume.env ]; then
  resume_cmd='sudo /opt/vast-host-installer/bin/vast-host-installer --resume'
  resume_text='Setup is waiting for manual resume. Run this command:'
  if grep -q '^NEXT_PHASE=after-nvidia-reboot$' /var/lib/vast-host-installer/resume.env 2>/dev/null || (command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1); then
    preflight_cmd='sudo /opt/vast-host-installer/bin/vast-host-installer --preflight-phase3'
    resume_cmd=''
    resume_text='Phase 3 is waiting. Run preflight first:'
  fi
fi

printf '%s%s' "$sky" "$bold"
cat <<'EOF'

██╗   ██╗ █████╗ ███████╗████████╗    ██╗  ██╗ ██████╗ ███████╗████████╗
██║   ██║██╔══██╗██╔════╝╚══██╔══╝    ██║  ██║██╔═══██╗██╔════╝╚══██╔══╝
██║   ██║███████║███████╗   ██║       ███████║██║   ██║███████╗   ██║
╚██╗ ██╔╝██╔══██║╚════██║   ██║       ██╔══██║██║   ██║╚════██║   ██║
 ╚████╔╝ ██║  ██║███████║   ██║       ██║  ██║╚██████╔╝███████║   ██║
  ╚═══╝  ╚═╝  ╚═╝╚══════╝   ╚═╝       ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝
EOF
printf '%s%s' "$sky" "$bold"
printf '\n VAST HOST Installer is ready.\n'
printf ' ------------------------------------------------------------------------\n'
printf ' Ubuntu is installed and the Vast bootstrap tools are on this host.\n\n'
printf ' %s\n\n' "$resume_text"
if [ -n "$preflight_cmd" ]; then
  printf '   %s\n' "$preflight_cmd"
fi
if [ -n "$resume_cmd" ]; then
  printf '   %s\n' "$resume_cmd"
fi
printf '%s' "$reset"
cat <<'EOF'

 ------------------------------------------------------------------------

EOF
