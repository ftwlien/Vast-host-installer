# Vast Host Installer v1.1.0 — Flawless King ISO

## Download

Recommended ISO:

```text
vast-host-installer-jammy-flawless-king.iso
```

SHA256:

```text
b919b259fd7842003cd20f14bd9a5ba3a27dc75675d416524756c602115788af  vast-host-installer-jammy-flawless-king.iso
```

Reserve ISO:

```text
vast-host-installer-jammy-perfection-reserve.iso
0026cf3b2b4be13a8677d26bd24443822a1b2fc3df3e25e4628d3d395768f6c6
```

## Description

This is the first Vast Host Installer ISO that feels like the thing we wanted from the start: flash it, boot it, let Ubuntu install, run one guided command, reboot when told, and come out the other side with a Vast-ready GPU host.

The ISO is built for operators who do not want to babysit a pile of fragile Linux commands. It stages the installer directly into the installed system, gives the rig a clean first-run wizard, walks through storage prep, NVIDIA setup, Vast bootstrap, optional extras, and final verification.

In short: **this ISO does the heavy lifting.**

## Beginner guide

1. Download `vast-host-installer-jammy-flawless-king.iso` from the release.
2. Flash it to a USB stick using balenaEtcher or Rufus.
3. Boot the target computer from that USB stick.
4. Let Ubuntu Server autoinstall finish.
5. Reboot into the installed system.
6. Log in and run:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --first-run
```

7. Answer the three setup sections:
   - machine identity
   - fresh Vast.ai host install command
   - optional extras: Vast CLI, rig-monitor, Fleet Health Check prerequisites
8. Reboot when the installer tells you.
9. Resume after each reboot with:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --resume
```

10. When Phase 3 completes, read the final install report and test/list the host in Vast.ai.

## Important beginner warning

Before booting the installer:

- back up anything important
- disconnect disks you do not want touched
- format/wipe the target disks first if you want the cleanest experience
- use a fresh Vast.ai install command for each rig/install attempt

The installer has detection and safety prompts, but the safest noob rule is: **if a disk matters, unplug it.**

## First-run setup before Phase 1

Before Phase 1 starts, the installer asks three groups of questions.

### 1/3 Machine identity

Sets the final hostname and operator user.

### 2/3 Vast bootstrap

Accepts the full Vast.ai host install command from the Vast.ai console. Generate a fresh command per machine.

### 3/3 Optional extras

- **Vast CLI**: installs local `vastai` command support
- **rig-monitor**: installs local GPU/rig monitoring and launcher
- **Fleet Health Check prerequisites**: installs helper dependencies/permissions for fleet diagnostics

## Phase overview

### Phase 1 — Storage and system prep

- detects the rig layout
- explains the storage plan
- prepares Docker/Vast storage
- updates/upgrades Ubuntu
- disables apt background jobs that can block installer work
- saves resume state

### Phase 2 — NVIDIA setup

- installs/refreshed recommended NVIDIA open driver
- prepares NVIDIA runtime basics
- enables persistence setup
- verifies GPU readiness
- saves resume state

### Phase 3 — Vast install and verification

- runs the official interactive Vast.ai installer
- verifies Docker, NVIDIA runtime, and Vast services
- repairs `vast_metrics` executable bit when needed
- installs optional extras
- prints a complete final install report

## Notable fixes in this build

- no bad Docker/NVIDIA pre-runtime conflict before Vast installer
- no logger/tee hang around the interactive Vast installer
- clearer Vast failure detection
- `vast_metrics` chmod/restart repair
- `rig-monitor` launcher fix
- blue/cyan terminal UI polish
- login banner says `VAST HOST`, not leftover `VAST AI`
- fixed literal escape reset text in banner output
- phase 3 preflight accepts valid Docker XFS split layouts
- final report shows exactly what was done
