# Custom ISO Plan

## Goal

Build a custom Ubuntu-based ISO for Vast hosts so an operator can:
- flash USB
- boot the rig
- install Ubuntu with the agreed storage policy
- log in with the bootstrap user
- run first-run setup
- finish with a Vast-ready host

## Final user experience target

1. flash ISO to USB
2. boot machine
3. Ubuntu autoinstall runs
4. machine reboots into installed OS
5. operator logs in via console/SSH
6. runs first-run setup (or is guided to it)
7. installer completes NVIDIA / Docker / Vast / extras

## What the ISO should contain

- Ubuntu autoinstall config
- bootstrap user config
- SSH enabled
- direct/no-LVM storage config
- Vast Host Installer payload staged into `/opt/vast-host-installer`
- first-run handoff notice/service

## Development strategy

### Phase 1
Keep building the installer engine and bootstrap artifacts.

### Phase 2
Create a reproducible ISO build directory that overlays:
- autoinstall files
- payload tarball
- bootstrap notes / helper service

### Phase 3
Build an actual custom ISO artifact.

## Important principle

The ISO is a delivery wrapper around:
- storage policy
- first-run flow
- installer payload

So the engine remains the source of truth.

## V1 ISO approach

The first ISO should probably:
- use the rendered `user-data`
- carry the installer payload tarball
- write it into `/opt/vast-host-installer`
- enable a notice that tells the operator to run first-run setup

That is already useful without pretending to be zero-touch magic.
