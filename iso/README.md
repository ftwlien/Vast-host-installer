# Vast Host Installer ISO

This directory contains the custom ISO scaffold for the Vast Host Installer.

Generated ISO files live in `iso/build/` and are intentionally ignored by git because they are huge. Public ISO downloads belong on the GitHub Releases page:

<https://github.com/ftwlien/Vast-host-installer/releases/latest>

## Recommended build

```text
vast-host-installer-jammy-v1.2.6.iso
```

SHA256: see the `.sha256` file attached to the GitHub release.

## What makes this ISO special

This is not just a plain Ubuntu ISO with a README slapped on top.

It is a purpose-built Vast.ai host installer image that:

- boots Ubuntu Server from USB
- stages the full installer payload into `/opt/vast-host-installer`
- creates the bootstrap handoff so the operator knows exactly what to run next
- carries the full three-phase Vast Host Installer workflow
- prepares Docker/Vast storage
- installs/refreshes the NVIDIA open-driver flow
- runs the official interactive Vast.ai host installer command
- verifies Docker, NVIDIA runtime, Vast services, and `vast_metrics`
- preserves existing Vast host port ranges
- installs optional Vast CLI, rig-monitor, Fleet Health Check prerequisites, aggressive GPU fan control, gpu-burn, CPU/RAM burn, and full-system burn tools
- installs useful host-polish commands like `vast_install_summary`, `storage_layout`, `vast_ready_check`, `disk_health`, `vast_system_update`, `vast_cleanup`, `vast_port_range`, and `vast_port_check`
- prints a clean final Phase 3 summary with logo, cyan boxes, green checkmarks, white text, quick stress commands, useful polish commands, and Vast CLI next steps

The ISO handles the boring infrastructure work so the operator can focus on the few things that must stay machine-specific: hostname, operator user, fresh Vast.ai install command, and optional extras.

## Beginner install flow

1. Download the ISO from GitHub Releases.
2. Flash it to USB with balenaEtcher or Rufus.
3. Boot the target rig from the USB stick.
4. Let Ubuntu Server autoinstall finish.
5. Remove the USB and reboot into the installed system.
6. Log in and run:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --first-run
```

7. Answer the first-run sections:
   - machine identity
   - Vast.ai bootstrap command
   - optional extras: Vast CLI, rig-monitor, Fleet Health Check prereqs, aggressive GPU fan control, gpu-burn, CPU/RAM burn
8. Reboot when the installer tells you.
9. Resume after each reboot with:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --resume
```

10. When Phase 3 finishes, read the final install report and test/list the machine in Vast.ai.

Optional extras can be installed or repaired later without rerunning the full setup:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --install-extras
```

## Existing Ubuntu rigs

Already-running Ubuntu rigs can get the same helper toolkit without reinstalling:

```bash
curl -fsSL https://raw.githubusercontent.com/ftwlien/Vast-host-installer/main/scripts/install-vast-host-tools.sh | sudo bash
```

Then run:

```bash
vast_install_summary
```

## Key commands after install

```bash
vast_install_summary
storage_layout
sudo vast_ready_check
sudo disk_health
sudo docker system df
sudo vast_system_update
sudo vast_cleanup
sudo vast_port_check
cpu_burn 60
sudo ram_burn 60
gpu_burn -tc -m 100% 60
full_burn 7200
sudo rig-burn-cleanup
```

## Build helpers

Current helper scripts:

- `../scripts/prepare-iso-scaffold.sh`
- `../scripts/build-custom-iso.sh`
- `../scripts/patch-iso-autoinstall-boot.sh`
- `../scripts/patch-casper-initrd-noise.sh`

Typical local generated artifacts:

- `iso/build/*.iso`
- `iso/overlay/vast-host-installer-payload.tgz`

These are ignored by git. Publish finished ISO files as GitHub Release assets.
