# Vast Host Installer Architecture

## Goal

Build a reliable Vast host installer that can eventually power:
- manual SSH-based installs
- generated install commands
- Ubuntu autoinstall hooks
- future custom ISO workflows

## Non-goal for v1

V1 is **not** a custom ISO.

V1 is the install engine.
If the logic is wrong, an ISO only makes failure prettier.

## Phases

### Phase 1 — Post-Ubuntu install engine
Assumptions:
- Ubuntu already installed
- SSH access works
- operator can run the installer on the target machine

Responsibilities:
- inspect hardware / disks
- classify layout
- pick install profile
- configure storage
- install NVIDIA / Docker / Vast
- install optional extras
- verify resulting state

### Phase 2 — Web generator
Responsibilities:
- ask operator what kind of rig this is
- output exact profile command
- explain what the installer will do
- reduce operator mistakes

### Phase 3 — Ubuntu autoinstall / ISO
Responsibilities:
- automate base OS provisioning
- attach install engine at the right phase
- eventually support full zero-touch deployment

## Core design rule

The install engine must be:
- profile-driven
- idempotent where possible
- explicit about destructive steps
- honest about what it can and cannot infer automatically

## Major subsystems

### 1. Detection
Collect:
- OS info
- GPU info
- disk inventory
- mount layout
- driver state
- Docker state
- Vast state

### 2. Planning
Turn facts into a plan:
- one-disk layout
- two-disk layout
- reinstall path
- same-machine-id intent vs clean-new-id intent

### 3. Execution
Run step modules:
- storage prep
- NVIDIA
- Docker
- Vast
- extras

### 4. Verification
Confirm:
- NVIDIA driver active
- Docker active
- NVIDIA runtime available
- Vast services healthy
- expected mount paths exist
- optional tools installed if requested

## Disk logic direction

### One disk
- OS and Vast/Docker data share one disk
- use a safe default layout
- avoid over-clever partitioning in v1

### Two disks
- boot/OS on smaller disk
- Docker/Vast data on larger disk
- mount and configure Docker/Vast storage paths there

### Later
- RAID/multi-storage variants
- explicit storage profile selection
- optional destructive repartition automation

## Extras layer
Optional components:
- rig-monitor
- gputemps
- fleet health prereqs
- security stack (later / separate)

## Safety stance

The engine should separate:
- read-only detection
- plan preview
- destructive apply

That means the future generator/installer can show:
- what was detected
- what will happen
- what disk/path choices are being made
before execution.
