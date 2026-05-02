# Profile Matrix

## Initial profiles

### fresh-basic
Use when:
- Ubuntu is already installed
- operator wants a standard Vast host bootstrap
- no fancy storage branching yet

Installs:
- NVIDIA
- Docker
- Vast

Optional:
- rig-monitor
- gputemps
- fleet-health prereqs

---

### fresh-single-disk
Use when:
- only one meaningful disk is present
- OS + Vast/Docker will live on same disk

Behavior:
- detect current root disk
- keep layout conservative in v1
- configure Docker/Vast paths for single-disk mode

---

### fresh-two-disk
Use when:
- one smaller boot disk
- one larger data disk

Behavior:
- keep OS on smaller/root disk
- use largest data disk for Docker/Vast storage
- mount and wire storage paths automatically

---

### reinstall-same-id
Use when:
- operator wants reinstall guidance around preserving expected machine identity behavior
- storage/state needs careful treatment

Behavior:
- explicit warnings
- stricter verification
- no hidden destructive actions

---

### reinstall-clean
Use when:
- operator wants a clean rebuild / new registration path

Behavior:
- reset-oriented flow
- no same-ID assumptions

---

## Extras flags

These should layer onto base profiles:
- `--with-rig-monitor`
- `--with-gputemps`
- `--with-fleet-health`

Later:
- `--with-security-stack`

## Operator principle

Profiles should stay understandable.
If a profile name needs a paragraph to explain, it is probably too vague.
