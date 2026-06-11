# Witness Wisp Accumulation Fix (gc-pack-86n)

## Problem
Witness patrol loop was accumulating unburned wisps because the formula could exit early (before reaching the `next-iteration` step that burns the current wisp). This caused wisps to pile up in "open" status instead of being burned.

Symptoms:
- 240+ open ephemeral beads assigned to witness agents
- Oldest wisps 24+ hours old, never updated after creation
- Patrol still running and creating new wisps, but not burning old ones

## Root Cause
The witness patrol formula has 5 steps: check-inbox, recover-orphaned-beads, check-refinery, check-polecat-health, next-iteration. Each step should continue to the next without exiting. However, if any step encountered an error or early return, the formula would exit without reaching `next-iteration`, leaving the wisp unburned.

The most likely culprit is the `recover-orphaned-beads` step, which involves complex jq operations for session liveness mapping. If jq parsing failed, session list parsing changed (like in the gc v1.1.1 schema migration), or the step timed out, it could exit early.

## The Fix

### Primary Fix: Witness Patrol Formula (gastown/formulas/mol-witness-patrol.toml)
- Added preamble in `next-iteration` that resolves current wisp ID at the start, before any other logic
- Added fail-safe: if pouring the next wisp fails, still burn the current wisp
- Improved burn logic with explicit success checking and error escalation
- Updated all earlier steps (recover-orphaned-beads, check-refinery, check-polecat-health) with explicit guidance to NOT exit on errors, and to continue to the next step

This ensures that even if earlier steps encounter errors, the formula continues to the burn step and wisps are burned.

### Secondary Fix: Cleanup Script (maintenance/assets/scripts/witness-wisp-burnall.sh)
Emergency cleanup script to manually burn accumulated old wisps. Safely identifies and burns all open witness wisps older than a threshold (default: 1 hour).

Usage:
```bash
cd /path/to/gascity-packs
bash maintenance/assets/scripts/witness-wisp-burnall.sh "gascity-packs-source/gastown.witness" 1
```

## Deployment

1. Merge these changes to the `live` branch of the gascity-packs fork
2. Run `gc import upgrade` in the town to pull in the updated witness patrol formula
3. The next witness patrol cycle will use the new formula with burn-fail-safe
4. Existing accumulated wisps will continue to be promoted to persistent by the hourly `wisp-compact` order (for stuck detection)
5. As a one-time cleanup, run the witness-wisp-burnall.sh script to manually burn old wisps if needed

## Verification

After deployment:
- Monitor `gc bd query --json 'ephemeral=true AND assignee~"witness"' | jq 'length'` — should stay at ~1-2 open wisps (the current active one)
- Check witness patrol logs for explicit FAILED messages (if pour/burn fails, it will mail the mayor)
- Old wisps will be promoted to persistent status by wisp-compact, appearing in `gc bd list --type=molecule --status=open` with comment "Promoted from wisp: open past TTL"

## Future Prevention
The fix makes the formula robust to errors and enforces the pour-and-burn contract. Additional improvements could include:
- Simpler recover-orphaned-beads step that fails gracefully
- Automatic wisp TTL checking to promote/delete old wisps
- Monitoring alerts for wisp accumulation patterns
