# Vast Host Installer

**A fast, no-bullshit Ubuntu Server ISO for building Vast.ai GPU hosts.**

This project turns a bare rig into a clean, repeatable, Vast-ready GPU host. Flash the ISO, boot the machine, answer the machine-specific questions, reboot when told, and the installer handles the boring/error-prone work: storage layout, Docker/Vast storage, NVIDIA drivers, Vast bootstrap, helper tools, stress tests, fan control, validation, and a clean final report.

The goal is simple: **make a fresh Vast host feel boringly reliable, even for people who have never installed a Linux GPU rig before.**

---

## Latest ISO

Download the latest release here:

<https://github.com/ftwlien/Vast-host-installer/releases/latest>

## Video walkthrough

Watch the full setup walkthrough here:

<https://www.youtube.com/watch?v=CbRVg3e9Duc>

Current recommended ISO:

- **`vast-host-installer-jammy-v1.iso`**
- Ubuntu Server 22.04 Jammy-based custom Vast.ai host ISO
- Boots/stages the installer cleanly from USB with a local payload at `/opt/vast-host-installer`
- Includes the polished Phase 3 summary, burn-test suite, port helpers, readiness checks, and existing-rig tools
- SHA256: see the `.sha256` file attached to the GitHub release

---

## Choose your install path

There are two first-class ways to build a Vast host with this project.

- **Path A — Custom ISO:** easiest, most guided, best for people who want the whole thing handled.
- **Path B — Official Ubuntu + installer script:** best for technical users who do not want to trust a custom ISO.

Both paths use the same guided Vast Host Installer UI after Ubuntu is installed: same logo, same phases, same reboot/resume flow, same final report.

---

## Path A — Easy mode: boot the custom ISO

Use this if you want the simplest install.

1. Download the release ISO.
2. Flash it to a USB stick.
3. Boot the rig from USB.
4. Follow the guided installer.
5. After each reboot, run the command shown on screen.

The ISO path handles Ubuntu install + Vast host setup in one guided flow.

This is the best choice if you want the installer to prepare the standard single-disk layout automatically:

```text
EFI:              1G
/:                100G ext4
/var/lib/docker:  rest of disk, XFS/prjquota
```

---

## Path B — Trust-first mode: official Ubuntu + installer script

Use this if you are more technical, or if you do not want to boot a custom ISO from the internet.

In this path, you install official Ubuntu Server yourself from Canonical, then run this open-source installer from GitHub.

This gives you the same ISO-style guided Vast setup UI, but without trusting a prebuilt ISO image. You can inspect the code, pin a release tag, and run it from source.

### 1. Install official Ubuntu Server

Download and install official Ubuntu Server 22.04.5 from Canonical.

When the Ubuntu installer asks about storage, use the normal official Ubuntu storage flow for your machine.

The official-Ubuntu bootstrap does **not** create, format, wipe, or mount Docker/Vast storage partitions. It leaves storage handling to the official Vast host installer/tooling.

### 2. Boot into Ubuntu

After Ubuntu finishes, boot into the installed system and make sure you have internet and sudo.

If you are on Proxmox or another VM platform, remove/eject the Ubuntu ISO and boot from disk. Use a full stop/start, not just reset, so the VM does not boot back into the installer.

### 3. Clone and inspect this repo

```bash
git clone https://github.com/ftwlien/Vast-host-installer.git
cd Vast-host-installer
git checkout main
```

`main` is the current working branch. For production/audited installs, use a release tag when one is published, for example `git checkout v1.2.0`.

Optional but recommended:

```bash
less scripts/install-clean-ubuntu-vast.sh
```

For production/audited installs, prefer a release tag once available. Until then, `main` is the current install path.

### 4. Run the official-Ubuntu bootstrap

```bash
sudo bash scripts/install-clean-ubuntu-vast.sh
```

This stages the installer at:

```text
/opt/vast-host-installer
```

Then it launches the same guided first-run flow used by the ISO, with one extra storage-safety mode:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --first-run --official-ubuntu
```

### 5. Storage behavior

There is no storage wizard in the official-Ubuntu path.

The bootstrapper does **not** create, format, wipe, or mount Docker/Vast storage partitions. Storage is left unchanged for the official Vast host installer/tooling.

### 6. Continue the same ISO-style phases

After Phase 1, reboot when told, then run:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --resume
```

After the NVIDIA phase and reboot, run the preflight check:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --preflight-phase3
```

Then start Phase 3:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --resume
```

Phase 3 runs the Vast.ai install command, installs selected extras, verifies Docker/NVIDIA/Vast services, and prints the final report.

### Trust model

The ISO is the easiest path, but it asks the user to trust a prebuilt boot image.

The official-Ubuntu path is better for skeptical or technical users because they can:

- download Ubuntu directly from Canonical
- clone this repository themselves
- inspect the scripts before running them
- pin a release tag or commit
- review diffs between versions
- run the installer from source

This does not remove all trust. The installer still runs as root because configuring Docker, NVIDIA, storage, and Vast requires root. But it is easier to audit than a prebuilt ISO.

Do not confuse this full installer path with the helper-only existing-rig script:

```bash
curl -fsSL https://raw.githubusercontent.com/ftwlien/Vast-host-installer/main/scripts/install-vast-host-tools.sh | sudo bash
```

That command only installs helper commands on an already-running machine. It is not the full Vast host setup flow.

---

## Why this ISO is better than a normal Ubuntu install

A normal Ubuntu installer gives you an operating system and then leaves you with a pile of manual GPU-host work:

- install/update NVIDIA correctly
- install Docker and NVIDIA container runtime
- prepare `/var/lib/docker` for Vast workloads
- run the Vast.ai host bootstrap command
- check services, ports, Docker, NVIDIA, storage, PCIe, and network
- build burn tools
- tune fans
- remember the right commands later

This ISO is different. It turns Ubuntu into a **purpose-built Vast host appliance**.

What you get:

- one repeatable install flow for every rig
- guided three-phase setup with resume after reboots
- storage planning before destructive disk work
- Docker/Vast storage prepared for real workloads
- NVIDIA open-driver setup and validation
- official Vast.ai installer handoff, then verification
- helper scripts installed globally so the rig is maintainable later
- burn/stress tools for proving stability before listing the machine
- clean final summary screen with exactly what was installed and what to run next
- a separate installer for already-running Ubuntu rigs, so existing machines can get the same toolkit without reinstalling

Short version: **normal installers give you Ubuntu. This gives you a standardized Vast.ai GPU host build.**

---

## What this ISO does

The ISO installs Ubuntu Server and stages the Vast Host Installer directly onto the machine. After Ubuntu is installed, the guided setup finishes the rig in phases.

It can:

- install Ubuntu Server from a USB stick
- use a custom autoinstall scaffold and local installer payload
- stage the installer in `/opt/vast-host-installer`
- create the temporary bootstrap login handoff
- ask for the final hostname/operator user/password at first run
- ask for a fresh Vast.ai host install command at first run
- detect single-disk vs multi-disk rigs
- explain the storage plan before destructive storage changes
- prepare `/var/lib/docker` correctly for Vast workloads
- support XFS/prjquota Docker storage checks
- run apt update/upgrade/dist-upgrade cleanup with noninteractive handling
- disable/mask background apt jobs that interfere with installs
- install/refresh the recommended NVIDIA open-driver flow
- configure NVIDIA persistence and headless Xorg/Coolbits basics when fan control is enabled
- run the official interactive Vast.ai host installer command
- verify Docker, NVIDIA, NVIDIA Docker runtime, Vast services, and metrics
- repair the known `vast_metrics` executable-bit issue when present
- preserve an existing Vast.ai host port range instead of overwriting it
- install Vast CLI
- install `rig-monitor`
- install Fleet Health Check prerequisites
- install aggressive Vast.ai GPU fan control
- install CPU, RAM, GPU, and full-system burn tools
- install cleanup/update/diagnostic/helper commands
- print a final Phase 3-style install report with logo, boxes, colors, and next commands

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
vast-host-installer-jammy-v1.iso
```

Optional but recommended: verify the SHA256 checksum matches the `.sha256` file attached to the release.

---

### Step 2 — Flash the ISO to a USB stick

Use one of these tools:

- **balenaEtcher**: easiest for most people
- **Rufus**: great on Windows

Basic flow:

1. Open balenaEtcher or Rufus.
2. Select `vast-host-installer-jammy-v1.iso`.
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
3. In BIOS/UEFI, disable Secure Boot if NVIDIA driver loading gives trouble.
4. Make sure the machine is connected to the internet.
5. If you want the cleanest install, wipe/format the target disks before starting Ubuntu setup.

The installer has disk detection and confirmation prompts, but do not gamble with important data. If a disk matters, disconnect it first.

---

### Step 4 — Boot from USB

1. Plug the USB stick into the rig.
2. Power on the rig.
3. Open the boot menu. Common keys: `F8`, `F11`, `F12`, `DEL`, or `ESC`.
4. Pick the USB stick.
5. Let Ubuntu Server autoinstall run.

When Ubuntu finishes, remove the USB stick if prompted and reboot into the installed system.

---

### Step 5 — Start the guided Vast setup

Log in with the temporary bootstrap account:

```text
username: vastbootstrap
password: vastbootstrap
```

Then start the guided setup immediately:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --first-run
```

The login screen also reminds you of this command. After first-run creates the final operator user, the temporary `vastbootstrap` account is locked when the final user is different.

After setup is finished and you have confirmed the final operator user can log in and use `sudo`, remove the temporary ISO bootstrap user:

```bash
sudo deluser --remove-home vastbootstrap
```

Verify only the intended admin user remains in the sudo group:

```bash
getent group sudo
```

---

## First-run questions

Before Phase 1 starts, the installer asks for the few things that should **not** be baked into a public ISO.

### Machine identity

The installer asks for:

- final hostname for the rig
- final operator username
- password for that operator user

This lets every rig get its own clean identity instead of cloning the same hostname/user forever.

### Vast bootstrap

The installer asks for:

- the full Vast.ai host install command from your Vast.ai console

Paste the whole command exactly. The Vast install command is interactive and may ask for port settings. Use a valid port range inside `1024-65535`.

Do **not** reuse an old/expired Vast install command. If in doubt, generate a fresh one.

### Optional extras

The installer asks if you want these extras:

#### Vast CLI

Installs the `vastai` command locally so you can later run commands like:

```bash
vastai set api-key YOUR_API_KEY
vastai show machines
vastai self-test machine YOUR_MACHINE_ID
```

#### rig-monitor

Installs Andy's `rig-monitor` tool for quick local rig checks.

After install:

```bash
rig-monitor
```

The installer creates a launcher so the bootstrap/operator shell can run it cleanly.

#### Fleet Health Check prerequisites

Installs prerequisites for Fleet Health Check tooling, including helper permissions needed for GPU/disk health checks.

This is useful if you manage multiple rigs and want consistent fleet diagnostics later.

#### Aggressive Vast.ai GPU fan control

Installs reboot-safe headless Xorg + fan-control services for NVIDIA rigs. The curve is tuned for Vast hosting stability:

- under 50°C → NVIDIA auto mode, so idle fans can stop
- 50–59°C → 50%
- 60–69°C → 75%
- 70–71°C → 90%
- 72°C and above → 100%

This is good for Vast rigs because loads can spike really fast. A renter can suddenly push the GPUs from idle to full load, and the normal NVIDIA auto fan curve can be too slow to react. By the time the fans catch up, the cards can already jump to 80–85°C.

This fan curve starts cooling earlier and ramps the fans harder under load, so it helps stop big temperature spikes and throttling. When the rig is idle and under 50°C, it goes back to auto mode so the fans don’t have to run hard all the time.

#### gpu-burn stress-test tool

Builds and installs [`wilicc/gpu-burn`](https://github.com/wilicc/gpu-burn) after the NVIDIA/CUDA phase, so you can load-test GPUs right after setup.

The installer creates:

- `/usr/local/bin/gpu_burn` — works from anywhere as `gpu_burn`
- `~/gpu_burn` — so from the operator home directory, `./gpu_burn` works too
- bash shortcut behavior so normal operator shells can launch it easily

Example 60-second full-memory test:

```bash
gpu_burn -tc -m 100% 60
```

The wrapper handles numeric-duration runs with a safe timeout grace window and treats the expected timeout completion cleanly, avoiding stuck orphan `gpu_burn` processes.

#### CPU/RAM burn and Memtest86+ tools

Installs `stress-ng`, `stressapptest`, and `memtest86+`, then creates simple global CPU and RAM load commands:

```bash
cpu_burn 60
sudo ram_burn 60
```

`cpu_burn` runs all CPU threads hard for the requested seconds.

`ram_burn` runs `stressapptest` with auto-sized memory and always includes:

```text
--pause_delay 999999
```

A `memtester` compatibility shim is kept for old habits, but the RAM burn backend is `stressapptest` because it behaves better for this use case.

Memtest86+ is installed for offline boot-menu memory testing when you want a deeper pre-OS RAM check.

#### Full-system burn test

If CPU/RAM and GPU burn tools are installed, the installer also creates:

```bash
full_burn 7200
```

That tests the whole machine by running RAM + CPU + GPU stress together for 2 hours, and writes timestamped logs under:

```text
~/burn-logs/
```

If something gets stuck after a burn test:

```bash
sudo rig-burn-cleanup
```

---

## Final summary screen

At the end, the installer prints a clean Phase 3 summary screen:

- big Vast Host logo/banner
- green success banner
- cyan box titles/borders
- green checkmarks
- white command text
- dedicated port-range box
- quick burn/stress-test command box
- useful host-polish command box
- optional Vast CLI next-steps box

You can reopen it anytime:

```bash
vast_install_summary
```

This is intentionally not a raw wall of logs. It is the human-readable “what happened and what do I run next?” screen.

---

## Installed utility commands

### Summary and layout

```bash
vast_install_summary
storage_layout
```

- `vast_install_summary` reopens the saved Phase 3 report.
- `storage_layout` shows disk/partition/mount/usage overview, including Docker XFS/prjquota status.

### Readiness and health

```bash
sudo vast_ready_check
sudo disk_health
sudo docker system df
```

- `sudo vast_ready_check` checks Docker, containerd, Vast services, `vast_metrics`, NVIDIA, NVIDIA Docker runtime, Docker root, XFS/prjquota, Secure Boot state, GPU PCIe links, and network speedtest when available.
- `sudo disk_health` shows disk layout, filesystem usage, and NVMe/SMART health.
- `sudo docker system df` shows Docker disk usage.

### Vast host port helpers

```bash
cat /var/lib/vastai_kaalia/host_port_range
sudo vast_port_range START-END
sudo vast_port_check
```

- The installer does **not** overwrite an existing Vast host port range.
- `vast_port_range` changes the range only when you ask it to.
- `vast_port_check` verifies the current config/helper state.

### Updates and cleanup

```bash
sudo vast_system_update
sudo vast_cleanup
```

- `sudo vast_system_update` updates apt packages, kernels, and Ubuntu/NVIDIA driver packages. Run only when idle/unlisted because reboot may be required.
- `sudo vast_cleanup` is an interactive Docker cleanup helper. It intentionally does **not** use `--volumes`.

Cleanup warning:

```text
vast_cleanup should only run when the machine is idle/unlisted and you are sure no customer data must be preserved.
```

### Burn/stress tests

```bash
cpu_burn 60
sudo ram_burn 60
gpu_burn -tc -m 100% 60
full_burn 7200
sudo rig-burn-cleanup
```

- `60` means seconds.
- Use `7200` for a 2-hour full burn-in.
- `full_burn` runs RAM + CPU + GPU together.
- logs are written under `~/burn-logs/`.
- `rig-burn-cleanup` kills stuck burn/stress-test leftovers.

### Vast CLI sanity checks

After setting your API key:

```bash
vastai --help
vastai set api-key YOUR_API_KEY
vastai show user
vastai show machines
vastai self-test machine YOUR_MACHINE_ID
vastai self-test machine YOUR_MACHINE_ID --ignore-requirements
```

More Vast CLI examples:

<https://docs.vast.ai/cli/hello-world>

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
- installs optional Vast CLI, rig-monitor, Fleet Health Check prereqs, GPU fan control, gpu-burn, and CPU/RAM burn tools
- saves the final summary to `/var/lib/vast-host-installer/final-summary.txt`
- prints the final polished install report

When Phase 3 finishes, the rig should be ready for Vast.ai listing/testing.

---


## Existing Ubuntu/Vast host maintenance installer

You do **not** need to reinstall with the ISO to use the maintenance tools.

The public helper installer can be run on any already-running Ubuntu Vast.ai host, including:

- rigs installed with an older version of this ISO
- rigs installed manually from normal Ubuntu
- existing Vast hosts that only need updated helper commands
- fleet machines that need the same maintenance tooling everywhere

Run:

```bash
curl -fsSL https://raw.githubusercontent.com/ftwlien/Vast-host-installer/main/scripts/install-vast-host-tools.sh | sudo bash
```

Then reopen the host summary any time with:

```bash
vastsetup
```

The old command still works too:

```bash
vast_install_summary
```

This helper installer does **not** reinstall Ubuntu and does **not** run the full ISO setup flow. It only installs/refreshes helper commands for maintenance, validation, burn testing, Vast CLI use, port checks, storage checks, and host polish.

It installs or refreshes tools such as:

- `vastsetup` — easy command to reopen the summary screen
- `vast_install_summary` — older summary command, kept for compatibility
- `vastai` — global wrapper for the Vast CLI
- `sudo vast_post_install_cleanup` — remove ISO/bootstrap leftovers when applicable
- `storage_layout`
- `sudo vast_ready_check`
- `sudo disk_health`
- `sudo vast_system_update`
- `sudo vast_cleanup`
- `sudo vast_port_range` / `sudo vast_port_check`
- `sudo vast_prepare_storage --plan`
- `cpu_burn`
- `ram_burn`
- `gpu_burn`
- `full_burn`
- `sudo rig-burn-cleanup`
- `sudo vast_install_gpu_burn`
- `sudo vast_install_gpu_fan_control`
- `sudo vast_gpu_fan_mode status|per-gpu|global`
- `rig-monitor` when available/installed

If gpu-burn ever needs repair:

```bash
sudo vast_install_gpu_burn
```

To add or repair Vast.ai GPU fan control on an already-running Ubuntu rig:

```bash
sudo vast_install_gpu_fan_control
```

Then choose/check the fan mode:

```bash
sudo vast_gpu_fan_mode status
sudo vast_gpu_fan_mode per-gpu
sudo vast_gpu_fan_mode global
```

This installs the same headless NVIDIA Xorg + `gpu-fan.service` fan-control stack used by the ISO Phase 3 flow.

Security note: when installing from the internet, inspect the script first if you want to verify it before running it with sudo:

```bash
curl -fsSL https://raw.githubusercontent.com/ftwlien/Vast-host-installer/main/scripts/install-vast-host-tools.sh -o install-vast-host-tools.sh
less install-vast-host-tools.sh
sudo bash install-vast-host-tools.sh
```

### Optional storage helper for clean-Ubuntu installs

The existing-Ubuntu tools include a guided storage helper:

```bash
sudo vast_prepare_storage --plan
sudo vast_prepare_storage
```

Policy:

- **1 disk:** the helper will not live-repartition the mounted root disk. Use the ISO/autoinstall path if you want automatic one-disk `100G /` plus XFS `/var/lib/docker` split before Ubuntu is installed.
- **2 disks:** Ubuntu/root must already be on the smaller disk. The helper can wipe the larger non-root disk, format it as XFS, and mount it at `/var/lib/docker` with `prjquota` after typed confirmation.

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

Install or repair optional extras later without rerunning the full installer:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --install-extras
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
- `scripts/` — build, ISO, reset, and existing-rig helper scripts
- `autoinstall/` — Ubuntu autoinstall scaffolding
- `iso/` — ISO scaffold/build notes; generated ISO artifacts are ignored by git
- `docs/` — design notes and architecture docs
- `systemd/` — first-run notice/auto-resume units

---

## Security notes

- Do not bake API keys, SSH private keys, or personal passwords into public ISOs.
- Anyone with an ISO can extract and inspect the installer payload.
- Use a fresh Vast.ai host install command for every machine/install attempt.
- The source repo does not track generated `iso/nocloud/user-data` or bootstrap password files.
- Generated ISO files are intentionally ignored by git and should be published as GitHub Release assets.

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
- aggressive Vast.ai GPU fan control optional install
- gpu-burn optional install for post-setup GPU stress testing
- stressapptest RAM burn with `--pause_delay 999999`
- CPU burn and full-system burn tools
- stuck burn cleanup helper
- Vast port range helpers
- system update and safe cleanup helpers
- existing Ubuntu rig host-tools installer
- final human-readable install report

Still planned:

- same-id reinstall profile
- clean reinstall profile
- richer generated storage policy matrix
- more public screenshots/videos/tutorial polish

---

## License

This project is **not MIT licensed**.

It is source-available for personal, educational, hobby, research, and other non-commercial use under the **FTWLIEN Non-Commercial License v1.0** in [`LICENSE`](LICENSE).

Commercial use is prohibited without prior written permission from the copyright holder. That includes hosting, resale, paid services, integration into commercial products or workflows, internal business use, or use by companies to support commercial GPU, AI, cloud, hosting, compute, or Vast.ai infrastructure.

Businesses and commercial users need a separate written commercial license. See [`COMMERCIAL_LICENSE.md`](COMMERCIAL_LICENSE.md).
