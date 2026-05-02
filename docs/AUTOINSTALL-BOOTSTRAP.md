# Ubuntu Autoinstall Bootstrap Layer

## Goal

Define the OS-side bootstrap that prepares the machine for the Vast Host Installer engine.

This layer should be generic and reusable.
Secrets and operator-specific choices belong in first-run setup, not in the baked autoinstall config.

## Bootstrap responsibilities

The autoinstall layer should:
- install Ubuntu Server
- avoid LVM by default
- enable SSH
- create a known bootstrap user
- place the Vast Host Installer on disk
- make first-run setup easy to launch

## Recommended bootstrap defaults

### User
Use a fixed bootstrap user for v1, for example:
- `vastbootstrap`

This avoids trying to make the ISO dynamically ask for custom account details during base OS install.

### SSH
- install `openssh-server`
- enable SSH at install time

### Installer location
Recommended location:
- `/opt/vast-host-installer`

## Storage direction

Use the agreed policy:
- 1 disk → Ubuntu + Docker/Vast on same disk
- 2 disks → Ubuntu on smallest, Docker/Vast on largest
- no LVM

The project now has the start of a policy-driven storage generator in:
- `scripts/generate-autoinstall-storage.py`

That generator currently emits the OS-install disk side of the autoinstall config.

## First-run handoff options

### Option A: explicit command
After first login, operator runs:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --first-run
```

### Option B: login notice
Autoinstall drops a message-of-the-day note telling the operator exactly what to run.

### Option C: systemd helper
Autoinstall creates a helper service/script that advertises first-run setup availability.

## V1 recommendation

Use:
- fixed bootstrap user
- SSH enabled
- installer copied to `/opt/vast-host-installer`
- login notice telling operator to run first-run setup

That is simpler and safer than trying to fully auto-launch an interactive setup wizard immediately.

## Future evolution

Later we can add:
- true autostart first-run wizard
- custom ISO branding
- PXE/autoinstall delivery
- generated autoinstall YAML from the same policy engine
