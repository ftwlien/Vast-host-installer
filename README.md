# Vast Host Installer

Opinionated installer framework for building and rebuilding Vast hosts.

This project is being built in layers:

1. **Install engine first**
   - disk detection
   - profile selection
   - storage layout logic
   - NVIDIA / Docker / Vast bootstrap
   - verification
2. **Web generator second**
   - choose profile/options
   - output exact commands / generated script
3. **Ubuntu autoinstall / ISO later**
   - once the install engine is trustworthy

## Why this order

A custom ISO is just a delivery wrapper.
The real hard part is the install logic:
- how disks are selected
- where Docker/Vast data goes
- how reinstallation is handled
- how verification is done safely

So v1 is **not** an ISO.
V1 is a real install engine that can later be embedded into an autoinstall or ISO flow.

## Initial target

Build a trusted post-Ubuntu installer that can:
- detect one-disk vs two-disk rigs
- use a separate Docker/Vast partition on single-disk autoinstall targets when the disk is large enough
- use the biggest non-root disk for /var/lib/docker on two-disk rigs
- install NVIDIA
- install Vast
- install Docker manually only if Vast setup explicitly needs it
- optionally install Vast CLI, rig-monitor (including GPU temp helper setup), and Fleet Health Check extras
- verify the final state

## Quick usage

### Portable post-install bootstrap on any machine

After installing Ubuntu from the ISO and logging in as `vastbootstrap`, run:

```bash
sudo apt update && sudo apt install -y git && git clone https://github.com/ftwlien/Vast-host-installer.git && cd Vast-host-installer && bash install/main.sh --first-run
```

This is the recommended path for fresh machines that do not have access to this bot's workspace or local network.

### Read-only detect

```bash
bash install/main.sh --detect-only
```

This now also shows the autoinstall-target disk policy view.

### Optional local install into /opt

```bash
bash scripts/install-into-opt.sh
```

Autoinstall/bootstrap scaffolding now exists in:
- `autoinstall/user-data.example.yaml`
- `autoinstall/README.md`
- `systemd/vast-host-installer-first-run-notice.service`
- `scripts/generate-autoinstall-storage.py`
- `scripts/render-autoinstall-user-data.py`
- `scripts/build-installer-payload.sh`
- `scripts/prepare-iso-scaffold.sh`
- `scripts/build-custom-iso.sh`
- `scripts/patch-iso-autoinstall-boot.sh`
- `iso/README.md`
- `docs/ISO-PLAN.md`
- `docs/ISO-BUILD-PIPELINE.md`

## Current ISO

Latest GitHub release download:

- <https://github.com/ftwlien/Vast-host-installer/releases/latest>

The ISO boots Ubuntu Server autoinstall and embeds the installer payload under:

- `/opt/vast-host-installer`

Local bot1 build path:

- `/home/bot1/.openclaw/workspace/vast-host-installer/iso/build/vast-host-installer-v1.0.6.iso`

After Ubuntu finishes and you log in, start setup with:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --first-run
```

Watch automatic phase resume after reboots with:

```bash
sudo journalctl -fu vast-host-installer-auto-resume.service
```

This mode now:
- asks for final hostname
- asks for final operator username + password
- asks for the full Vast install command from Vast.ai
- lets the Vast installer itself handle the host port range prompt
- can optionally install the Vast CLI locally before the other extras
- can optionally install Fleet Health Check prerequisites from the public repo

If you choose the optional Vast CLI install, the CLI is installed on the host for later use. After the full host install is finished, you can set your API key and verify it with:

```bash
vastai set api-key YOUR_API_KEY
vastai show user
```

### Reset installer-added tools for another test run

If you want to rerun the flow from a mostly clean slate without reinstalling Ubuntu, use:

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
- detects whether the machine is single-disk or two-disk
- explains the storage plan in plain English and asks for confirmation before destructive disk changes
- phase 1: applies storage prep + full system updates
- then tells you to reboot
- phase 2 after reboot: installs/configures NVIDIA open drivers
- then tells you to reboot again
- phase 3 after second reboot: verifies NVIDIA, runs the Vast install command, and finishes setup

Resume after each reboot:

```bash
bash install/main.sh --resume
```

The script saves its own resume state during phase 1 and phase 2, so you no longer need to paste long resume commands.

Direct phase-3 style apply example:

```bash
bash install/main.sh --profile fresh-two-disk --vast-install-command 'PASTE_VAST_COMMAND_HERE' --resume-after-nvidia-reboot --apply
```

For destructive two-disk storage apply, the installer now requires the exact target disk to be confirmed explicitly.

## Planned structure

- `docs/`
  - design docs
  - profile matrix
  - disk rules
  - future autoinstall notes
- `install/`
  - install engine
  - shared library functions
  - profile definitions
- `web/`
  - first generator UI
- `bin/`
  - entrypoint wrappers

## Status

Scaffold / engine phase started.

Current state:
- docs + profile matrix in place
- first web generator mock in place
- install engine skeleton exists
- detect-only path works
- one-disk vs two-disk classification works
- autoinstall disk-target policy module exists
- first-run workflow mode exists
- `--plan-only` preview mode exists
- human-readable plan summary exists
- single-disk phase-1 storage apply exists for post-Ubuntu installs (100G for /, rest for /var/lib/docker); autoinstall uses the same split on disks >=140GiB and falls back to root-only on smaller disks
- two-disk phase-1 storage apply exists (largest non-root disk goes to /var/lib/docker)
- plain-English storage confirmation prompts exist for destructive disk changes
- three-phase manual flow exists (prep/update, NVIDIA, Vast)
- first-pass Vast install module exists
- first-pass verification layer exists
- autoinstall/bootstrap scaffolding exists
- USB-bootable ISO release path exists and v0.1.2 has passed a real bare-metal boot test

Still missing / still rough:
- same-id / clean reinstall profiles
- richer autoinstall storage generation from policy
- more real-world validation of the single-disk live shrink/apply path
- polish for user wording and noob-proof UX
