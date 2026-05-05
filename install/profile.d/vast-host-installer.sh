#!/bin/sh

case "$-" in
  *i*) ;;
  *) return 0 2>/dev/null || exit 0 ;;
esac

[ -t 1 ] || return 0 2>/dev/null || exit 0
[ ! -f /var/lib/vast-host-installer/setup-complete ] || return 0 2>/dev/null || exit 0
[ -x /opt/vast-host-installer/bin/vast-host-installer ] || return 0 2>/dev/null || exit 0

cat <<'EOF'

 __     ___    ____ _____      _    ___
 \ \   / / \  / ___|_   _|    / \  |_ _|
  \ \ / / _ \ \___ \ | |     / _ \  | |
   \ V / ___ \ ___) || |    / ___ \ | |
    \_/_/   \_\____/ |_|   /_/   \_\___|

 Vast Host Installer is ready.
 ----------------------------------------------------------------
 Ubuntu is installed and the Vast bootstrap tools are on this host.

 Run this command to continue setup:

   sudo /opt/vast-host-installer/bin/vast-host-installer --first-run
 ----------------------------------------------------------------

EOF
