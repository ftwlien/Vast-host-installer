# Vast Host Installer ISO - Post-install security cleanup update

Use this text for the ISO/release description after the new ISO has been tested.

## What changed

- Added a new **Post-install security cleanup** section to the final Phase 3 summary and `vast_install_summary` output.
- Added a short helper command for the whole cleanup flow:
  - `sudo vast_post_install_cleanup`
- Cleanup now reminds the operator to run it only after the final sudo user is confirmed working and Vast is verified.
- Cleanup now removes sensitive/temporary installer leftovers, including:
  - saved Vast install command state: `/var/lib/vast-host-installer/resume.env`
  - temporary Vast installer files: `/tmp/vast-install.sh`, `/tmp/vast-install.*`
  - Ubuntu autoinstall/cloud-init user-data files that may contain bootstrap password hashes
  - optional installer debug logs if no longer needed
  - leftover `vastbootstrap` sudoers entries
  - completed installer login/autoresume hooks
  - installer-only apt/needrestart noninteractive override files
  - optional staged installer payload if the operator does not need rerun/debug ability
- Shortened the manual update helper label to fit the summary box:
  - `sudo vast_system_update - Manual updates when idle`

## Important behavior kept intentionally

The ISO still disables/purges unattended apt jobs during setup. Do **not** undo this for Vast rental rigs:

```bash
sudo apt purge --auto-remove unattended-upgrades -y
sudo systemctl disable apt-daily-upgrade.timer
sudo systemctl mask apt-daily-upgrade.service
sudo systemctl disable apt-daily.timer
sudo systemctl mask apt-daily.service
```

Reason: this avoids surprise apt locks, driver changes, or update activity while a rig is rented. Security/system updates are manual with:

```bash
sudo vast_system_update
```

Run that only when the host is idle/unlisted.

## Testing checklist before publishing

1. Boot the ISO on a test host/VM.
2. Complete Phase 1/2/3.
3. Confirm final summary shows **Post-install security cleanup**.
4. Confirm `vast_install_summary` reopens the same cleanup section.
5. Confirm the cleanup box shows `sudo vast_post_install_cleanup`.
6. Confirm `sudo vast_system_update - Manual updates when idle` stays on one line in the box.
7. Confirm Vast/Docker/NVIDIA services still work after following cleanup commands.
