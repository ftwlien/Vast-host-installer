# Security Policy

## Supported versions

Security fixes are applied to the latest release and current `main` branch.

## Reporting a vulnerability

Please report security issues privately to the repository owner instead of opening a public issue with exploit details.

## Important ISO security notes

- Do **not** bake Vast.ai API keys, SSH private keys, cloud tokens, or personal passwords into a public ISO.
- The generated `iso/nocloud/user-data` file and bootstrap password files are local build artifacts and are intentionally ignored by git.
- Anyone who downloads an ISO can extract it and inspect the installer payload. Treat ISO contents as public.
- The temporary `vastbootstrap` account is only for first login/handoff. After `--first-run` creates the final operator user, the installer locks the bootstrap account when the final user is different.
- Always use a fresh Vast.ai host install command per machine/install attempt.
- Verify SHA256 checksums before flashing release ISOs.
