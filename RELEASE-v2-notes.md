# Vast Host Installer v2 — Smarter Cooling, Cleaner Setup, Safer Post-Install

This release is the next tested ISO after **Vast Host Installer v1 — Polished Vast-Ready Host ISO**.

v2 keeps the same goal as v1: get an Ubuntu 22.04 Vast.ai GPU host from bare metal to a usable, rentable machine with the least manual work possible. The new release focuses on the things we learned while installing and operating the fleet after v1: better final-screen guidance, safer cleanup after installation, easier repeat summaries, better host helper tools, switchable GPU fan modes, and a cleaner standalone update path for machines that are already installed.

> Existing v1 release assets are left untouched. This is a new release with new assets.

## Assets

- `vast-host-installer-jammy-v2.iso`
- `vast-host-installer-jammy-v2.iso.sha256`

SHA256:

```text
7a43907ec85b7506fe64949a2b1abe0e77261bce6f34527a0df54532b69adf43  vast-host-installer-jammy-v2.iso
```

## Quick install flow

1. Download the ISO and checksum from this release.
2. Verify it:

   ```bash
   sha256sum -c vast-host-installer-jammy-v2.iso.sha256
   ```

3. Write the ISO to USB, or mount/boot it through your server/IPMI tooling.
4. Boot the target rig from the ISO.
5. Follow the installer prompts.
6. When Phase 3 finishes, use the final summary screen to verify ports, cleanup, stress tests, and Vast CLI commands.

## Install/refresh tools on any existing Ubuntu Vast host

You do **not** need to reinstall with the ISO to use the helper tools.

On any already-running Ubuntu Vast.ai host — whether it was installed with this ISO, an older ISO, or manually from normal Ubuntu — run:

```bash
curl -fsSL https://raw.githubusercontent.com/ftwlien/Vast-host-installer/main/scripts/install-vast-host-tools.sh | sudo bash
```

This installs/refreshes the standalone host tools without reinstalling the OS. Use it for maintenance, fleet updates, manually-installed machines, or rigs that only need the newest helper commands.

## Big changes since v1

### 1. New `vastsetup` summary command

The final setup screen can now be reopened with a much easier command:

```bash
vastsetup
```

The old command still works too:

```bash
vast_install_summary
```

The final summary now has a dedicated **Setup summary** box showing both commands, placed below post-install cleanup and above the Vast CLI section.

### 2. Cleaner final Phase 3 screen

The Phase 3 completion screen was reorganized so it is easier to use while standing at a fresh rig.

The final screen now groups information like this:

1. What was done — full install report
2. Vast.ai host port range
3. Quick stress-test commands
4. Useful host polish commands
5. Post-install security cleanup
6. Setup summary
7. Optional next steps — Vast CLI

The goal is simple: after the installer finishes, the operator can immediately see what happened, what to verify, what cleanup to run, and how to bring the screen back later.

### 3. Post-install security cleanup helper

v2 adds/expands the installed cleanup helper:

```bash
sudo vast_post_install_cleanup
```

The cleanup helper removes installer/bootstrap leftovers after the final sudo user works and Vast has been verified.

It is designed for the common case where the rig is fully installed and you no longer need temporary ISO bootstrap material lying around.

Cleanup covers things like:

- temporary bootstrap users such as `vastbootstrap`
- the default `ubuntu` user when present and no longer needed
- saved installer resume/env files
- temporary Vast installer logs/scripts
- cloud-init/autoinstall seed user-data that can contain bootstrap details
- subiquity/curtin/cloud-init installer logs
- first-run/autoresume installer hooks
- staged installer payloads
- installer-only apt/needrestart noninteractive override files

After cleanup runs, the cleanup section is removed from the saved final summary so the summary is less cluttered going forward.

Optional deeper cleanup is still available:

```bash
sudo vast_post_install_cleanup --remove-installer
```

### 4. Switchable GPU fan modes

v2 adds a GPU fan mode helper:

```bash
sudo vast_gpu_fan_mode status
sudo vast_gpu_fan_mode per-gpu
sudo vast_gpu_fan_mode global
```

#### `global` mode

This is the old/simple behavior: the hottest GPU controls the fan curve for the machine.

It is predictable and safe as a fallback.

#### `per-gpu` mode

This is the new smarter mode.

It attempts to auto-discover which physical fan belongs to which GPU, then controls fans per GPU instead of forcing every fan to follow the hottest GPU.

If fan mapping cannot be discovered safely, it falls back to the global fan curve instead of leaving the machine unmanaged.

#### `status`

Shows current configured/running mode plus a quick GPU temperature/fan/utilization snapshot.

### 5. Vast CLI install/update improvements

The standalone host-tools installer now installs or upgrades the Vast CLI for the real operator user with:

```bash
python3 -m pip install --user --upgrade vastai
```

It also installs a global wrapper at:

```text
/usr/local/bin/vastai
```

This means after running the host tools installer, the usual Vast CLI commands should work directly:

```bash
vastai --help
vastai set api-key YOUR_API_KEY
vastai show user
vastai show machines
vastai self-test machine YOUR_MACHINE_ID
vastai self-test machine YOUR_MACHINE_ID --ignore-requirements
```

More Vast CLI examples:

https://docs.vast.ai/cli/hello-world

### 6. Port range helper visibility

The final summary keeps the Vast host port range front and center:

```bash
cat /var/lib/vastai_kaalia/host_port_range
sudo vast_port_range START-END
sudo vast_port_check
```

This makes it easier to verify forwarded ports match what Vast expects before listing or testing a rig.

### 7. Stress-test and host-polish command guidance

The final summary includes practical commands for burn/stress testing and maintenance, including helpers such as:

```bash
cpu_burn
ram_burn
gpu_burn
full_burn
rig-burn-cleanup
sudo vast_system_update
sudo vast_install_gpu_fan_control
sudo vast_gpu_fan_mode status
sudo vast_gpu_fan_mode per-gpu
sudo vast_gpu_fan_mode global
```

`vast_system_update` wording was clarified: use it for manual security/system updates only when the rig is idle/unlisted.

Automatic unattended upgrades remain disabled by design for Vast hosts, to avoid surprise apt locks, driver changes, or reboots during rentals.

### 8. Existing-rig host tools script now carries the new helpers

The raw installer:

```bash
curl -fsSL https://raw.githubusercontent.com/ftwlien/Vast-host-installer/main/scripts/install-vast-host-tools.sh | sudo bash
```

now carries the newer helper set, including:

- `vastsetup`
- `vast_install_summary`
- `vast_post_install_cleanup`
- `vastai` wrapper
- `vast_ready_check`
- `disk_health`
- `storage_layout`
- `vast_port_range`
- `vast_port_check`
- burn/stress helpers
- GPU fan control installer
- GPU fan mode switcher

### 9. Cleanup reliability fixes

A few cleanup edge cases were fixed while testing on real rigs:

- installer log directory cleanup now uses directory-safe removal where needed
- final summary cleanup section removes itself after cleanup
- cleanup reopens the clean summary via `vastsetup`
- sudoers validation is performed after cleanup edits

### 10. Tested on the live fleet workflow

This ISO and the related host-tools updates were tested against the real Vast host workflow:

- fresh ISO install flow
- final summary rendering
- port range verification
- Vast CLI availability
- fleet dashboard integration
- fleet health prerequisites
- fleet security stack deployment
- GPU temperature helpers
- post-install cleanup behavior

## After installing

Recommended operator flow after Phase 3 completes:

1. Verify the final summary.
2. Check Vast port range:

   ```bash
   sudo vast_port_check
   ```

3. Check the Vast CLI:

   ```bash
   vastai --help
   ```

4. Optionally set API key and inspect machines:

   ```bash
   vastai set api-key YOUR_API_KEY
   vastai show user
   vastai show machines
   ```

5. Run any stress tests you want before listing.
6. Once final sudo user and Vast are verified, run:

   ```bash
   sudo vast_post_install_cleanup
   ```

7. Bring the final screen back any time with:

   ```bash
   vastsetup
   ```

## Notes

- v1 remains available as-is.
- v2 is intended for new installs and for people who want the newer cleanup/fan-mode/final-summary behavior.
- Existing hosts do not need a reinstall just to get helper updates; use the raw `install-vast-host-tools.sh` command above.
