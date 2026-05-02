# ISO Build Pipeline

## Goal

Turn the ISO scaffold into an actual custom Ubuntu ISO build workflow.

## Current inputs

Prepared by `scripts/prepare-iso-scaffold.sh`:
- `iso/nocloud/user-data`
- `iso/nocloud/meta-data`
- `iso/overlay/vast-host-installer-payload.tgz`

## Recommended build strategy

### V1
Use an Ubuntu ISO remaster flow that:
1. mounts/extracts the upstream Ubuntu ISO
2. injects NoCloud autoinstall data
3. injects the installer payload tarball
4. updates boot parameters to point at autoinstall data
5. rebuilds a bootable ISO artifact

### Why this first
It gives a real image artifact without committing to a more complex PXE or image pipeline yet.

## Main decisions still to lock

- exact Ubuntu base ISO version/source
- exact remaster toolchain (`xorriso`, `7z`, loop mount, etc.)
- NoCloud placement path in the ISO
- bootloader parameter updates for autoinstall
- how payload tarball is made available to the installed target

## Honest current status

The project still does not output a final bootable custom ISO yet.

But the build scaffold now can:
- extract an upstream Ubuntu ISO
- stage NoCloud files into the extracted tree
- stage the installer payload overlay into the extracted tree
- apply a first real Jammy-targeted GRUB autoinstall patch when supported files exist

The missing steps are now:
- extend boot patching if more bootloader paths are required
- validate the current payload handoff path into the installed target under a real install run
- validate the rebuilt ISO candidate as actually bootable/installable for the target Jammy flow
