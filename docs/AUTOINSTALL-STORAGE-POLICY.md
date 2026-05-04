# Autoinstall Storage Policy

## Final target rule

### 1 disk
- install Ubuntu on the only disk
- keep Docker/Vast on the same disk
- do not require a separate Docker partition during autoinstall
- no LVM

### 2 disks
- install Ubuntu on the **smallest** disk
- use the **largest** disk for Docker/Vast data
- no LVM

### Ambiguous
If the machine has:
- more than 2 plausible disks
- disks with unclear roles
- conflicting existing storage state
- surprising pre-existing partitions/layouts
then automation should stop instead of guessing.

## Why this differs from current post-Ubuntu detection

The current engine can detect the already-installed root disk and then choose the largest non-root disk.
That is useful for post-install automation.

But the final autoinstall-aware policy must reason **before** Ubuntu is placed:
- which disk becomes OS/root
- which disk becomes Docker/Vast data

That means the final logic needs explicit small-disk / large-disk ranking.

## Ranking model

For the clean two-disk case:
- sort disks by size ascending
- smallest disk = Ubuntu target
- largest disk = Docker/Vast target

If only one disk exists:
- use it for both. The autoinstall path should prefer a root-only layout unless
  the target disk is known to be large enough for an additional data partition.

If 3+ plausible disks exist:
- stop and require operator review

## Filesystem direction

### OS/root disk
- ext4
- no LVM

### Docker/Vast data disk
- XFS
- mounted at `/var/lib/docker`
- only emitted automatically for the clean two-disk autoinstall case

## Future autoinstall output

Later the project should be able to generate:
- Ubuntu autoinstall storage config
- matching post-install data-mount logic

using the same policy source of truth.
