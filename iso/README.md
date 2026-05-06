# Vast Host Installer ISO

This directory contains the custom ISO scaffold for the Vast Host Installer.

Generated ISO files live in `iso/build/` and are intentionally ignored by git because they are huge. Public ISO downloads belong on the GitHub Releases page:

<https://github.com/ftwlien/Vast-host-installer/releases/latest>

## Recommended build

```text
vast-host-installer-jammy-v1.2.0.iso
```

SHA256: see the `.sha256` file attached to the GitHub release.

## What makes this ISO special

This is not just a plain Ubuntu ISO with a README slapped on top.

It is a purpose-built Vast.ai host installer image that:

- boots Ubuntu Server autoinstall from USB
- uses RAM-oriented boot/install flags for a smooth install
- stages the installer payload into `/opt/vast-host-installer`
- creates the bootstrap handoff so the operator knows exactly what to run next
- carries the full three-phase Vast Host Installer workflow
- supports optional Vast CLI, rig-monitor, Fleet Health Check prerequisites, aggressive GPU fan control, gpu-burn, and CPU burn stress testing

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

7. Answer the three first-run sections:
   - machine identity
   - Vast.ai bootstrap command
   - optional extras: Vast CLI, rig-monitor, Fleet Health Check prereqs, aggressive GPU fan control, gpu-burn, CPU burn
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

## First-run sections before Phase 1

Before Phase 1 starts, the ISO-staged installer asks the operator three blocks of questions.

### 1/3 Machine identity

- final hostname
- final operator username
- operator password

### 2/3 Vast bootstrap

- full fresh Vast.ai host install command

This should be generated fresh from the Vast.ai console for every rig/install attempt.

### 6/6 Optional extra choices

- **Vast CLI**: installs the local `vastai` command and wrapper
- **rig-monitor**: installs local rig/GPU monitoring and a clean launcher
- **Fleet Health Check prerequisites**: installs prerequisites and helper permissions for fleet diagnostics
- **Aggressive GPU fan control**: installs reboot-safe NVIDIA Xorg/fan services tuned for Vast.ai hosting
- **gpu-burn stress test**: builds `wilicc/gpu-burn` after NVIDIA/CUDA setup, installs `gpu_burn` globally, and adds a bash shortcut so `./gpu_burn` works from normal operator shells
- **CPU burn stress test**: installs `stress-ng` and creates `cpu_burn 60` for a clean all-core CPU stress test from anywhere
- **Full burn test**: when CPU and GPU burn are installed, creates `full_burn 7200` for a 2-hour combined CPU+GPU burn-in

## Phase summary

### Phase 1 — Storage and system prep

- disk/layout detection
- storage plan explanation
- Docker/Vast storage prep
- apt update/upgrade/dist-upgrade
- disables background apt timers that can block install work
- saves resume state

### Phase 2 — NVIDIA setup

- installs/refreshed recommended NVIDIA open driver
- prepares NVIDIA runtime basics
- enables persistence mode setup
- verifies GPU readiness
- saves resume state

### Phase 3 — Vast, extras, verification

- runs the official interactive Vast.ai installer command
- verifies Docker, NVIDIA runtime, and Vast services
- repairs/restarts `vast_metrics` when needed
- installs optional CLI/rig-monitor/fleet-health/fan-control extras
- prints a full final install report

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
