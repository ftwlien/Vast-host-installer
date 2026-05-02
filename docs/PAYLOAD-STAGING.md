# Payload Staging

## Goal

Turn the autoinstall flow into a real bootstrap delivery path.

That means the installed machine should receive a copy of the Vast Host Installer at:
- `/opt/vast-host-installer`

not just a message telling the operator what to run later.

## Current scaffold

The project now includes:
- `scripts/build-installer-payload.sh`

This creates a tarball payload containing the installer project files.

## Intended autoinstall direction

The final bootstrap flow should do something like:
1. build installer payload tarball
2. make it available to the installer environment
3. copy/extract it into `/target/opt/vast-host-installer`
4. enable the first-run notice or first-run helper

## Why this matters

Without payload staging, the autoinstall file only describes the OS install.
With payload staging, the installed host actually contains the installer engine needed for the next step.

## Current limitation

We have the payload build step, but not yet the final integrated delivery mechanism into a custom ISO or a hosted artifact path.

That is okay for now.
The important thing is that the project now has a defined payload artifact shape.
