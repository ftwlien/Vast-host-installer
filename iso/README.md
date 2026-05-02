# ISO Scaffold

This directory is the start of the custom ISO layer.

## Intended contents

- `overlay/`
  - files to be injected into the installed target / installer environment
- `nocloud/`
  - autoinstall `user-data` and related files
- `build/`
  - generated ISO build artifacts

## Current helper scripts

- `../scripts/prepare-iso-scaffold.sh`
  - stages NoCloud files and installer payload
- `../scripts/build-custom-iso.sh`
  - starts the custom ISO build pipeline scaffold

## Direction

The first custom ISO should combine:
- rendered autoinstall `user-data`
- installer payload tarball
- bootstrap handoff to `/opt/vast-host-installer`

## Honest current status

This is still scaffold, but it is now more than empty directories.

The current build script can:
- extract an upstream Ubuntu ISO into a work tree
- stage NoCloud autoinstall files
- stage the installer payload overlay
- attempt a first rebuilt custom ISO candidate output

That rebuilt ISO still needs real boot/install validation.
