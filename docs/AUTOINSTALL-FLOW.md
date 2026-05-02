# Autoinstall + First-Run Flow

## Target model

### Phase 1: Ubuntu autoinstall / ISO
The OS layer should:
- install Ubuntu Server
- avoid LVM by default
- create a known bootstrap user
- enable SSH
- place the Vast Host Installer on the machine
- optionally trigger a first-run setup wizard automatically

### Phase 2: first-run setup
The first-run script should:
- ask for Vast API key
- ask for final hostname
- optionally create/set the final operator user and password
- infer install profile when safe
- allow optional extras
- continue through the installer automatically

## Why split it this way

Secrets and operator-specific choices should not be baked into the ISO.
That means things like:
- Vast API key
- final hostname
- maybe optional extras
belong in first-run setup, not the base OS image.

## Storage policy

### One disk
- install Ubuntu on that disk
- keep Docker/Vast on that disk
- no LVM

### Two disks
- install Ubuntu on the smallest disk
- use the largest disk for Docker/Vast data
- no LVM

### Ambiguous layouts
If the machine has:
- more than two plausible disks
- existing conflicting storage state
- unclear device roles
then the automation should stop instead of guessing.

## Bootstrap user model

Recommended simple model:
- autoinstall creates a fixed bootstrap user
- operator logs in with that user
- first-run script asks for the remaining data

This is easier than trying to make the ISO dynamically ask for custom account details.

## First-run questionnaire fields

Minimum:
- Vast API key
- final hostname
- Vast host port range

Optional / recommended:
- final operator username
- final operator password
- install rig-monitor
- install gputemps
- install fleet-health prereqs

Conditional:
- if layout is ambiguous, ask what to do
- if reinstall profile is needed later, ask for reinstall intent

## UX direction

### Clean case
If disk layout is obvious:
- installer auto-selects profile
- installer auto-selects storage targets
- operator only provides API key + hostname + optional extras
- installer can also create/set the final operator user if requested

### Weird case
If disk layout is ambiguous:
- installer refuses to guess
- asks for operator intervention or exits with a clear reason

## Future ISO hook points

Later, the autoinstall can:
- include the installer project in `/opt/vast-host-installer`
- create a systemd unit or login notice for first-run setup
- present the operator with a command like:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer-first-run
```

That becomes the bridge between bare Ubuntu install and full Vast-ready host.
