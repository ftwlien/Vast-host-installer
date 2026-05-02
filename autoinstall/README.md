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

The generator currently emits only the **OS install disk** side of the autoinstall storage config.
It does **not** yet generate the post-install data-disk mount logic — that still lives in the installer engine.

That split is intentional for now.

## Example render

```bash
python3 scripts/render-autoinstall-user-data.py --mode auto --hostname vast-bootstrap --username vastbootstrap
```
