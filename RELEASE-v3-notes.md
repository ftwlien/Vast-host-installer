RTX 5090 / Blackwell support, CUDA 13.2 burn tooling, and automatic multi-NVMe RAID0 Docker storage for Vast.ai hosts.

This release keeps the installer simple for beginners while making the resulting Vast host much better suited for modern rental workloads.

## Headline changes

### Automatic ISO storage layout

The ISO now plans storage like a purpose-built Vast host instead of a generic Ubuntu box:

- smallest suitable internal disk becomes Ubuntu/EFI/boot
- one extra internal data disk becomes XFS Docker/Vast storage at `/var/lib/docker`
- two or more extra internal data disks become Linux `mdadm` RAID0 at `/dev/md0`
- `/dev/md0` is formatted XFS and mounted at `/var/lib/docker` with `prjquota`
- USB/removable installer media is excluded from disk selection

Example:

```text
/dev/nvme0n1  -> Ubuntu OS / EFI / boot
/dev/nvme1n1  -> RAID0 member
/dev/nvme2n1  -> RAID0 member
/dev/md0      -> XFS /var/lib/docker
```

RAID0 is used for performance/capacity, not redundancy. It is appropriate for Vast scratch/cache/container storage, but users should not store irreplaceable data on it.

### RTX 5090 / Blackwell burn tooling

The optional gpu-burn installer now handles Blackwell systems properly:

- detects RTX 50 / RTX 5090 / Blackwell hosts
- removes old CUDA 11/12 toolkit packages without removing NVIDIA drivers
- installs NVIDIA CUDA Toolkit 13.2 (`cuda-toolkit-13-2`)
- points `/usr/local/cuda` to `/usr/local/cuda-13.2`
- builds gpu-burn with `COMPUTE=120 CUDAPATH=/usr/local/cuda-13.2 CUDA_VERSION=13.2.0`
- forces rebuilds on Blackwell hosts so stale pre-Blackwell binaries are not reused

### Host safety and polish

- adds Vast machine-ID helper for reinstall/disk-replacement workflows
- keeps persistent GPU power limits as an explicit opt-in helper, not a default
- adds Docker fallback before the Vast install phase if Docker is missing/inactive
- strengthens storage, Docker, NVIDIA runtime, Vast service, and burn-tool verification

## Recommended asset

```text
vast-host-installer-jammy-v3.iso
```

Check the attached `.sha256` file before flashing.
