# Next Steps

## Immediate engineering target

Turn the engine scaffold into a trustworthy read-only planner before destructive automation.

## Step 1
Strengthen detection:
- root disk resolution
- candidate non-root disks
- mounted/unmounted state
- filesystem presence
- largest usable non-root disk selection
- ambiguous layout detection

## Step 2
Make two-disk storage planning concrete:
- root stays on current boot disk
- largest non-root disk becomes Docker/Vast data target
- show mount/format plan before execution

## Step 3
Port proven rig-onboarding logic carefully:
- pull from `dashboard/rig-onboarding/install-vast-prereqs.sh`
- adapt into modular steps, not one giant script blob
- keep destructive storage actions explicit

## Step 4
Wire in verification:
- nvidia-smi
- docker active
- nvidia runtime available
- expected mount exists

## Principle

Read-only planning first.
Destructive apply second.
