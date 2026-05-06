# Vast Host Installer

**A fast, no-bullshit Ubuntu Server ISO for building Vast.ai GPU hosts.**

This project turns a bare rig into a clean Vast-ready host with a guided, three-phase installer. Flash the ISO, boot the machine, answer a few questions, reboot when told, and the installer handles the annoying parts: storage layout, system prep, NVIDIA driver setup, Vast bootstrap, Docker/NVIDIA verification, rig-monitor, and optional Fleet Health Check prep.

The goal is simple: **make a fresh Vast host feel boringly reliable, even for people who have never installed a Linux GPU rig before.**

---

## Latest ISO

Download the latest release here:

<https://github.com/ftwlien/Vast-host-installer/releases/latest>

Current recommended ISO:

- **`vast-host-installer-jammy-flawless-king.iso`**
- Ubuntu Server Jammy-based custom autoinstall ISO
- Boots the USB and installer into RAM for a fast, clean install experience
- Installer payload is embedded locally at `/opt/vast-host-installer`
- SHA256:

```text
b919b259fd7842003cd20f14bd9a5ba3a27dc75675d416524756c602115788af  vast-host-installer-jammy-flawless-king.iso
```

Reserve/fallback build:

```text
0026cf3b2b4be13a8677d26bd24443822a1b2fc3df3e25e4628d3d395768f6c6  vast-host-installer-jammy-perfection-reserve.iso
```

---

## What this ISO does

The ISO installs Ubuntu Server and stages the Vast Host Installer directly onto the machine. After Ubuntu is installed, the guided setup finishes the rig in phases.

It can:

- install Ubuntu Server from a USB stick
- use RAM boot/install flags for a smoother install
- create the bootstrap login user
- stage the installer in `/opt/vast-host-installer`
- detect single-disk vs multi-disk rigs
- explain the storage plan before destructive storage changes
- prepare `/var/lib/docker` correctly for Vast workloads
- run apt update/upgrade/dist-upgrade cleanup
- disable/mask unattended apt jobs that interfere with installs
- install the recommended NVIDIA open driver flow
- configure NVIDIA persistence/Coolbits basics
- run the official interactive Vast.ai host install command
- verify NVIDIA, Docker, Docker NVIDIA runtime, and Vast services
- repair the known `vast_metrics` executable-bit issue when present
- optionally install Vast CLI
- optionally install `rig-monitor`
- optionally install Fleet Health Check prerequisites
- print a final full install report so you know what happened

In plain English: **the ISO gets Ubuntu on the box, then the installer does the Vast host build for you.**

---

## Super easy noob guide

### What you need

- A GPU rig/server you want to turn into a Vast.ai host
- A USB stick, usually 8GB or bigger
- The latest ISO from the GitHub release page
- A fresh Vast.ai host install command from your Vast.ai console
- Keyboard/monitor or SSH access after Ubuntu installs

> Important: generate a **fresh** Vast.ai host install command for each machine/install attempt. Old/reused commands can fail with `401 Unauthorized`.

---

### Step 1 — Download the ISO

Go to:

<https://github.com/ftwlien/Vast-host-installer/releases/latest>

Download:

```text
vast-host-installer-jammy-flawless-king.iso
```

Optional but recommended: verify the SHA256 checksum matches the value shown in the release notes.

---

### Step 2 — Flash the ISO to a USB stick

Use one of these tools:

- **balenaEtcher**: easiest for most people
- **Rufus**: great on Windows

Basic flow:

1. Open balenaEtcher or Rufus.
2. Select `vast-host-installer-jammy-flawless-king.iso`.
3. Select your USB stick.
4. Click flash/start.
5. Wait until it finishes.
6. Safely eject the USB stick.

This erases the USB stick. Do not pick the wrong drive.

---

### Step 3 — Prepare the target rig

Before booting the installer, make life easy:

1. Back up anything important from the rig.
2. Remove disks you do **not** want touched if you are unsure.
3. In the BIOS/UEFI, disable Secure Boot if NVIDIA driver loading gives trouble.
4. Make sure the machine is connected to the internet.
5. If you want the cleanest install, wipe/format the target disks before starting Ubuntu setup.

The installer has disk detection and confirmation prompts, but do not gamble with important data. If a disk matters, disconnect it first.

---

### Step 4 — Boot from the USB stick

1. Plug the USB stick into the rig.
2. Power on the rig.
3. Open the boot menu. Common keys: `F8`, `F11`, `F12`, `DEL`, or `ESC`.
4. Pick the USB stick.
5. Let Ubuntu Server autoinstall run.

The ISO is designed so Ubuntu installs quickly and cleanly. On a decent rig, this should feel much smoother than a manual Ubuntu install.

When Ubuntu finishes, remove the USB stick if prompted and reboot into the installed system.

---

### Step 5 — Log in after Ubuntu installs

Log in as the bootstrap user shown by the installer/login notice.

Then start the guided setup:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --first-run
```

The login screen also reminds you of this command.

---

## The 3 questions before Phase 1

Before Phase 1 starts, the installer asks a short first-run questionnaire. This is where you provide the machine-specific stuff that should **not** be baked into a public ISO.

### 1/3 — Machine identity

The installer asks for:

- final hostname for the rig
- final operator username
- password for that operator user

This lets every rig get its own clean identity instead of cloning the same hostname/user forever.

### 2/3 — Vast bootstrap

The installer asks for:

- the full Vast.ai host install command from your Vast.ai console

Paste the whole command exactly. The Vast install command is interactive and may ask for port settings. Use a valid port range such as something inside `1024-65535`.

Do **not** reuse an old/expired Vast install command. If in doubt, generate a fresh one.

### 3/3 — Optional extras

The installer asks if you want these extras:

#### Vast CLI

Installs the `vastai` command locally so you can later run commands like:

```bash
vastai set api-key YOUR_API_KEY
vastai show machines
vastai self-test machine YOUR_MACHINE_ID
```

#### rig-monitor

Installs Andy’s `rig-monitor` tool for quick local rig checks.

After install, you should be able to run:

```bash
rig-monitor
```

The installer creates a launcher so the bootstrap/operator shell can run it cleanly without manually jumping into the `vast` user.

#### Fleet Health Check prerequisites

Installs prerequisites for the Fleet Health Check tooling, including helper permissions needed for GPU/disk health checks.

This is useful if you manage multiple rigs and want consistent fleet diagnostics later.

---

## Installer phases

### Phase 1 — Storage and system prep

Runs after `--first-run`.

Phase 1:

- sets the final hostname
- creates the operator user
- detects the disk layout
- explains the storage plan
- prepares Docker/Vast storage
- runs base system update/upgrade prep
- disables apt background jobs that can block installs
- saves resume state
- tells you to reboot

After reboot, log in and run:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --resume
```

---

### Phase 2 — NVIDIA setup

Runs after the first reboot/resume.

Phase 2:

- installs/refreshed the recommended NVIDIA open driver
- prepares NVIDIA runtime basics
- enables persistence mode setup
- checks whether NVIDIA is working
- saves resume state for the final Vast phase
- tells you to reboot again

After reboot, log in again and run:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --resume
```

Optional preflight check before Phase 3:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --preflight-phase3
```

---

### Phase 3 — Vast install, extras, and verification

Runs after the NVIDIA reboot.

Phase 3:

- checks that the machine is ready
- runs the official Vast.ai host installer command interactively
- lets Vast handle its own Docker/NVIDIA package flow
- fixes/restarts `vast_metrics` if the Vast metrics launcher is not executable
- verifies Docker
- verifies NVIDIA inside Docker
- verifies Vast services
- installs optional Vast CLI, rig-monitor, and Fleet Health Check prereqs
- prints a final install report

When Phase 3 finishes, the rig should be ready for Vast.ai listing/testing.

---

## Common commands

Start first-run setup:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --first-run
```

Resume after a reboot:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --resume
```

Run Phase 3 preflight:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --preflight-phase3
```

Watch auto-resume service logs if needed:

```bash
sudo journalctl -fu vast-host-installer-auto-resume.service
```

Run rig monitor after setup:

```bash
rig-monitor
```

Test Vast CLI after setup:

```bash
vastai set api-key YOUR_API_KEY
vastai show machines
vastai self-test machine YOUR_MACHINE_ID
vastai self-test machine YOUR_MACHINE_ID --ignore-requirements
```

---

## Disk/layout notes

The installer supports these fresh-install layouts:

- **single-disk rigs**: root plus Docker/Vast storage split when the disk is large enough
- **two-disk/multi-disk rigs**: root stays on the OS disk; the largest suitable non-root disk can be used for `/var/lib/docker`
- **valid Docker XFS split layouts**: accepted even when the Docker partition is on the same physical disk as root

The installer explains the planned storage layout before applying destructive storage changes. Still, the safest beginner rule is simple:

> If you do not want a disk touched, unplug it before installing.

---

## Developer/local usage

Read-only detection:

```bash
bash install/main.sh --detect-only
```

Plan preview:

```bash
bash install/main.sh --plan-only
```

Portable post-install bootstrap on any Ubuntu machine:

```bash
sudo apt update && sudo apt install -y git && git clone https://github.com/ftwlien/Vast-host-installer.git && cd Vast-host-installer && bash install/main.sh --first-run
```

Optional local install into `/opt`:

```bash
bash scripts/install-into-opt.sh
```

Reset installer-added tools for another test run:

```bash
bash scripts/reset-host-installer-state.sh --yes
```

This removes installer-added userland extras and helper repos such as:

- Vast CLI user install
- `~/rig-monitor`
- `~/Fleet-Health-Check-public`
- `rig-monitor` launcher files
- `gputemps` helper files added by these extras
- local installer resume state

It does **not** fully undo:

- NVIDIA driver installation
- Docker installation
- system packages installed by earlier phases
- live Vast host configuration already applied by Vast's own installer

---

## Repo structure

- `install/` — installer engine and phase logic
- `scripts/` — build, ISO, reset, and helper scripts
- `autoinstall/` — Ubuntu autoinstall scaffolding
- `iso/` — ISO scaffold/build notes; generated ISO artifacts are ignored by git
- `docs/` — design notes and architecture docs
- `systemd/` — first-run notice/auto-resume units

---

## Status

The current ISO flow has passed real-rig testing and is now the recommended path for fresh Vast host builds.

Implemented:

- USB-bootable Ubuntu Server ISO path
- embedded installer payload
- RAM-oriented boot/install polish
- first-run questionnaire
- three-phase resume workflow
- single/multi-disk detection
- Docker/Vast storage prep
- NVIDIA open-driver setup
- Vast interactive installer handoff
- Docker/NVIDIA/Vast verification
- `vast_metrics` executable repair
- Vast CLI optional install
- rig-monitor optional install and launcher
- Fleet Health Check prerequisites optional install
- final human-readable install report

Still planned:

- same-id reinstall profile
- clean reinstall profile
- richer generated storage policy matrix
- more public screenshots/videos/tutorial polish
