# Autoinstall Scaffolding

This directory is the start of the Ubuntu autoinstall layer.

## Current pieces

- `user-data.example.yaml`
  - first conservative static example
- `../scripts/generate-autoinstall-storage.py`
  - emits a storage YAML fragment from the agreed disk policy
- `../scripts/render-autoinstall-user-data.py`
  - renders a fuller `user-data` file using the storage policy generator
- `../scripts/build-installer-payload.sh`
  - builds the tarball payload meant to be staged into `/opt/vast-host-installer`

## Intended direction

The final autoinstall flow should:
- avoid LVM
- use direct storage layout
- select the smallest disk for Ubuntu
- leave the largest disk for Docker/Vast data when 2 disks exist
- stop instead of guessing on ambiguous layouts

## Current limitation

The ISO scaffold renders `--mode auto` as a bootstrap autoinstall file. Its
early command runs the renderer again from the ISO overlay, inside the target
installer environment, and rewrites `/autoinstall.yaml` using the VM/server's
own `lsblk` output. This is important on Proxmox: resolving `auto` at ISO build
time bakes in the builder's disk layout and can hand curtin a storage plan that
does not match the VM.

For one-disk autoinstall targets, the generated layout now keeps Docker/Vast on
the root filesystem instead of forcing a separate 100G-root-plus-XFS remainder
layout. That avoids curtin partitioning failures on common 100G-or-smaller
virtual disks. Two-disk targets still mount the largest disk at
`/var/lib/docker`.

## Example render

```bash
python3 scripts/render-autoinstall-user-data.py --mode auto --hostname vast-bootstrap --username vastbootstrap
```
