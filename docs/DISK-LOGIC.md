# Disk Logic Notes

## Immediate target

Support the common operator case:
- **1 disk** → keep OS + data on same disk
- **2 disks** → Ubuntu on the smallest disk, Docker/Vast data on the largest disk

## V1 constraints

V1 should prefer:
- detecting current root disk
- identifying other candidate data disks
- mounting/configuring data paths

V1 should avoid trying to be a universal repartitioning wizard.
That becomes dangerous fast.

## Detection rules to build

### Root disk
Determine:
- current root mount source
- underlying block device
- parent disk

### Candidate data disks
Collect for each disk:
- size
- model
- transport
- mount state
- filesystem presence
- partition table presence
- whether already in use

### Simple classification

#### one-disk
If only root disk exists as a meaningful usable device.

#### two-disk
If:
- root disk exists
- one clearly larger non-root disk exists

#### ambiguous
If:
- more than two disks
- equal-sized disks
- existing mounts/state conflict
- RAID/LVM already present

Ambiguous cases should not silently guess.

## Two-disk policy direction

Preferred final heuristic:
- choose the smallest disk for Ubuntu / boot / root
- choose the largest disk for Docker/Vast data
- use the largest disk for Docker/Vast storage paths

During the current post-Ubuntu engine phase, root-disk detection still matters because Ubuntu is already installed.
But the final autoinstall-aware design target is:
- smallest disk = OS
- largest disk = Docker/Vast data

## Future extension

Later profiles can support:
- RAID
- explicit disk selector flags
- clean destructive repartition mode
- autoinstall storage config generation
