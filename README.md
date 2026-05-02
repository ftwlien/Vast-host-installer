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
- use 100G for / and the rest for /var/lib/docker on single-disk rigs
- use the biggest non-root disk for /var/lib/docker on two-disk rigs
- install NVIDIA
- install Docker
- install Vast
- optionally install rig-monitor / gputemps / fleet-health extras
- verify the final state

## Quick usage

Read-only detect:

```bash
bash install/main.sh --detect-only
```

This now also shows the autoinstall-target disk policy view.

Install the project into the future bootstrap location:

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

## Current ISO testing artifact

GitHub release download:

- <https://github.com/ftwlien/Vast-host-installer/releases/download/v0.1.0/vast-host-installer-jammy-custom.iso>

Local bot1 build path:

- `/home/bot1/.openclaw/workspace/vast-host-installer/iso/build/vast-host-installer-jammy-custom.iso`

Read-only plan preview:

```bash
bash install/main.sh --profile fresh-two-disk --plan-only
```

First-run workflow mode:

```bash
bash install/main.sh --first-run
```

This mode now:
- asks for final hostname
- asks for final operator username + password
- asks for Vast host port range
- asks for the full Vast install command from Vast.ai
- infers a profile
- applies storage prep + full system updates first
- then tells you to reboot and resume with the printed command

Resume after reboot:

```bash
sudo VAST_INSTALL_COMMAND='PASTE_VAST_COMMAND_HERE' VAST_PORT_RANGE='40000-40019' bash install/main.sh --profile fresh-basic --resume-after-reboot --apply
```

Direct apply for real:

```bash
bash install/main.sh --profile fresh-two-disk --vast-install-command 'PASTE_VAST_COMMAND_HERE' --vast-port-range 40000-40019 --confirm-disk /dev/YOUR_DATA_DISK --resume-after-reboot --apply
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
- one-disk vs two-disk classification skeleton exists
- autoinstall disk-target policy module exists
- first-run workflow mode exists
- `--plan-only` preview mode exists
- human-readable plan summary exists
- single-disk policy targets 100G for / and the rest for /var/lib/docker
- two-disk storage planning is explicit
- first real two-disk storage apply function exists
- first-pass Vast install module exists
- first-pass verification layer exists
- autoinstall/bootstrap scaffolding exists

Still missing:
- real single-disk storage apply policy
- same-id / clean reinstall profiles
- richer autoinstall storage generation from policy
- final ISO build layer
