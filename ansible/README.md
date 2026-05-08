# Vast Host Installer Ansible v1

This is the transparent path for people who do **not** want to boot a custom ISO from a third-party GitHub repo.

The model is:

1. Install the official Ubuntu Server ISO yourself.
2. Enable SSH during Ubuntu install.
3. Run this Ansible playbook from your workstation.
4. Review the plan/logs on the target.
5. Run the Vast.ai bootstrap command manually, or opt into running it through Ansible.

## How this differs from the ISO

The ISO is a bare-metal installer. It boots before Ubuntu exists, installs Ubuntu, stages the project, and runs the guided Vast host setup.

Ansible v1 starts **after official Ubuntu is already installed**. That means you manually handle:

- booting the official Ubuntu ISO
- OS disk/root filesystem choices in the Ubuntu installer
- user creation
- SSH enablement
- GPU passthrough/VM hardware setup, if this is a VM

Ansible v1 can then handle most post-Ubuntu host setup:

- apt prep/upgrades
- optional separate Docker/Vast data disk formatting/mounting
- HWE kernel install (`linux-generic-hwe-22.04` + headers)
- Docker install
- NVIDIA driver install
- NVIDIA container runtime
- host helper tools
- optional fan-control helper
- readiness output
- staging or optionally running the Vast.ai bootstrap command

## HWE kernel

For Ubuntu 22.04 GPU hosts, Ansible v1 explicitly installs:

```bash
linux-generic-hwe-22.04
linux-headers-generic-hwe-22.04
```

A normal `apt upgrade` updates the current kernel track, but does not always switch a GA-kernel install onto HWE. The playbook installs HWE explicitly and reboots before NVIDIA driver setup when the kernel packages changed.

## Storage safety

Ansible v1 does **not** silently repartition the live OS/root disk.

If you want separate Docker/Vast storage, attach a separate empty data disk and explicitly set both:

```yaml
vast_apply_storage: true
vast_docker_disk: /dev/nvme1n1
```

The playbook refuses to format the detected root disk. Destructive storage work is opt-in on purpose.

## Quick start

Copy the inventory:

```bash
cp ansible/inventory.example.ini ansible/inventory.ini
```

Edit `ansible/inventory.ini` and add your host:

```ini
[vast_hosts]
10.26.26.123 ansible_user=ubuntu
```

Run:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbooks/clean-ubuntu.yml --ask-become-pass
```

On the target, review:

```bash
sudo cat /var/lib/vast-host-installer/ansible-plan-preview.txt
sudo cat /var/lib/vast-host-installer/ansible-v1-next-steps.txt
sudo cat /var/lib/vast-host-installer/ansible-vast-ready-check.txt
```

## Guided storage helper

The host-tools installer also provides:

```bash
sudo vast_prepare_storage --plan
sudo vast_prepare_storage
```

It follows the same safe policy as Ansible v1:

- 1 disk: do not live-repartition the mounted root disk.
- exactly 2 disks: root must already be on the smaller disk; the larger non-root disk can be wiped/formatted/mounted at `/var/lib/docker` after typed confirmation.
- 3+ disks: stop and require manual review.

## Optional data disk example

Only do this when `/dev/nvme1n1` is a disposable non-root data disk:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbooks/clean-ubuntu.yml \
  --ask-become-pass \
  -e vast_apply_storage=true \
  -e vast_docker_disk=/dev/nvme1n1
```

This creates one XFS partition and mounts it at `/var/lib/docker` with project quota options.

## Vast.ai bootstrap

By default, the playbook does **not** silently run the Vast.ai host bootstrap command because it is often interactive and machine-specific.

Recommended flow:

1. Generate a fresh Vast.ai host install command in the Vast console.
2. SSH into the host.
3. Run it where you can see/respond to prompts.
4. Run `sudo vast_ready_check` afterward.

If you want Ansible to stage the command as a root-only helper script:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbooks/clean-ubuntu.yml \
  --ask-become-pass \
  -e 'vast_install_command=YOUR_FULL_FRESH_VAST_INSTALL_COMMAND'
```

Then on the host:

```bash
sudo /root/run-vast-bootstrap.sh
```

If you explicitly want Ansible to run the command, set:

```yaml
vast_run_vast_bootstrap: true
vast_install_command: "YOUR_FULL_FRESH_VAST_INSTALL_COMMAND"
```

Use that only if you know the command will not require interactive input.

## Auditability

For maximum auditability, pin this before running:

```yaml
vast_host_installer_repo_version: "v1"
```

or use a specific commit hash instead of `main`.
