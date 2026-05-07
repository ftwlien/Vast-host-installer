# Vast Host Installer v1.2.6 — Polished Vast-Ready Host ISO

## Download

Recommended ISO:

```text
vast-host-installer-jammy-v1.2.6.iso
```

SHA256: see the `.sha256` file attached to the GitHub release.

## What this release is

This is the polished Vast Host Installer ISO: a custom Ubuntu Server 22.04 image that turns a bare rig into a standardized Vast.ai GPU host with guided setup, storage prep, NVIDIA setup, Vast bootstrap, helper scripts, burn tests, fan control, and final validation.

A normal Ubuntu installer gives you Ubuntu. This ISO gives you the whole Vast host toolkit.

## Highlights

- Custom Ubuntu Server Jammy ISO with embedded installer payload at `/opt/vast-host-installer`
- Guided three-phase install/resume workflow
- First-run machine identity setup: hostname, operator user, operator password
- Fresh Vast.ai host install command prompt during setup
- Single-disk and multi-disk storage planning
- Docker/Vast storage prep with XFS/prjquota validation
- NVIDIA open-driver setup and verification
- Official interactive Vast.ai host installer handoff
- Docker, NVIDIA runtime, Vast service, and `vast_metrics` verification/repair
- Existing Vast host port range is preserved instead of overwritten
- Dedicated Vast host port helper commands: `vast_port_range` and `vast_port_check`
- Polished final `vast_install_summary` screen with logo, cyan boxes, green checkmarks, and clean command sections
- Separate `Useful host polish commands` box so helper commands are readable and copyable
- Clean `Quick stress-test commands` box for burn tools only

## Included operator tools

### Summary and diagnostics

```bash
vast_install_summary
storage_layout
sudo vast_ready_check
sudo disk_health
sudo docker system df
```

### Vast port helpers

```bash
cat /var/lib/vastai_kaalia/host_port_range
sudo vast_port_range START-END
sudo vast_port_check
```

### System update and cleanup

```bash
sudo vast_system_update
sudo vast_cleanup
```

`vast_cleanup` is intentionally interactive and does not use Docker `--volumes`.

Warning:

```text
vast_cleanup should only run when the machine is idle/unlisted and you are sure no customer data must be preserved.
```

### Burn/stress testing

```bash
cpu_burn 60
sudo ram_burn 60
gpu_burn -tc -m 100% 60
full_burn 7200
sudo rig-burn-cleanup
```

Notes:

- `cpu_burn` uses `stress-ng`.
- `ram_burn` uses `stressapptest` with auto-sized memory and `--pause_delay 999999`.
- `memtester` remains as a compatibility shim.
- `gpu_burn` wraps numeric-duration runs with a safe timeout/grace flow and avoids orphan `gpu_burn` leftovers.
- `full_burn 7200` runs RAM + CPU + GPU together for a 2-hour burn-in and writes logs under `~/burn-logs/`.
- `rig-burn-cleanup` kills stuck burn/stress-test leftovers.

## Optional extras

The ISO can install:

- Vast CLI (`vastai`)
- `rig-monitor`
- Fleet Health Check prerequisites
- aggressive Vast.ai GPU fan control with reboot-safe headless Xorg/fan services
- gpu-burn
- CPU/RAM burn tools
- full-system burn tool

## Existing Ubuntu rig installer

Already-running Ubuntu rigs can get the same toolkit without reinstalling:

```bash
curl -fsSL https://raw.githubusercontent.com/ftwlien/Vast-host-installer/main/scripts/install-vast-host-tools.sh | sudo bash
```

Then run:

```bash
vast_install_summary
```

This installs the Phase 3-style summary, validation tools, port helpers, burn tools, cleanup/update helpers, and existing-rig polish commands.

## Quick install flow

1. Download `vast-host-installer-jammy-v1.2.6.iso` from GitHub Releases.
2. Flash it with balenaEtcher or Rufus.
3. Boot the rig from USB.
4. Let Ubuntu Server autoinstall finish.
5. Reboot into the installed system.
6. Run:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --first-run
```

7. Reboot/resume when prompted:

```bash
sudo /opt/vast-host-installer/bin/vast-host-installer --resume
```

8. At Phase 3 completion, run/check:

```bash
vast_install_summary
sudo vast_ready_check
full_burn 7200
```

## Security notes

- Do not bake API keys, SSH private keys, or personal passwords into public ISOs.
- Anyone with the ISO can extract and inspect the installer payload.
- Use a fresh Vast.ai host install command for every install attempt.
- Generated ISO files are published as GitHub Release assets, not tracked in git.
