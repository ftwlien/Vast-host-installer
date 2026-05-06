# Vast Host Installer v1.2.0 — Burn Tools + Fan Control ISO

## Download

Recommended ISO:

```text
vast-host-installer-jammy-v1.2.0.iso
```

SHA256: see the `.sha256` file attached to the GitHub release.

## What is new

This release adds the polished optional-extras flow and post-install stress testing tools:

- aggressive NVIDIA GPU fan control option with reboot-safe `nvidia-xorg.service` and `gpu-fan.service`
- `gpu_burn -tc -m 100% 60` GPU stress-test command
- `cpu_burn 60` CPU stress-test command using `stress-ng`
- `memtester 60` dedicated RAM test command using `memtester`
- Memtest86+ package installed for boot-menu/offline memory testing
- `full_burn 7200` combined CPU+GPU+RAM 2-hour burn-in command with `~/burn-logs` output
- `vast_install_summary`, `storage_layout`, `sudo vast_ready_check`, `sudo disk_health`, `sudo docker system df`, `sudo vast_system_update`, and `sudo vast_cleanup` operator/helper commands
- single public repo helper `scripts/install-vast-host-tools.sh` for adding the Phase 3-style summary, validation tools, and CPU/RAM burn tools to existing Ubuntu rigs without reinstalling
- `--install-extras` mode for installing or repairing optional extras later without rerunning storage/Vast setup
- cleaner `6/6 Optional extra choices` prompt with short explanations
- final quick stress-test command box
- non-interactive Phase 1 apt/needrestart handling to avoid blue package popups
- temporary `vastbootstrap` account is locked after the final operator user is created

## Quick test commands after install

```bash
cpu_burn 60
memtester 60
gpu_burn -tc -m 100% 60
full_burn 7200
# full_burn tests the whole machine: RAM + CPU + GPU together
vast_install_summary
storage_layout
sudo vast_ready_check
sudo disk_health
sudo docker system df
sudo vast_system_update
vastai --help
vastai show user
vastai show machines
rig-monitor
```

`60` means seconds. Use `7200` for a 2-hour burn-in.

## Security notes

- Do not bake API keys, SSH private keys, or personal passwords into public ISOs.
- Anyone with an ISO can extract and inspect the installer payload.
- The source repo does not track generated `iso/nocloud/user-data` or bootstrap password files.
- Use a fresh Vast.ai host install command for every machine/install attempt.
