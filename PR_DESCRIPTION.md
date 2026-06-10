# fix(maintenance): rig-scope watchdog + suppress idle-dev-rig false positives

## Summary

Two bugs in `maintenance/assets/scripts/rig-liveness-watchdog.sh` that together
caused noisy, duplicate incident mail on multi-rig cities and false stall alerts
on quiet dev rigs.

---

## Bug 1 — ~4x concurrent runs racing the shared ledger

**Root cause.** The Gas City controller already fans every exec order out per
scope: it creates one invocation for the HQ/global scope (empty `$GC_RIG`) and
one per configured rig (with `$GC_RIG` stamped to that rig's name). The
watchdog script was unaware of this and looped all rigs internally with
`gc rig list` on every invocation. On a four-rig city that produced roughly 4×
concurrent runs, each iterating all four rigs, all writing to a single shared
ledger file (`rig-liveness-incidents.json`). The concurrent writes raced,
producing duplicate `[INCIDENT]` escalation mails for the same event.

**Fix.** Rig-scope the watchdog identically to its sibling `orphan-sweep`:

- Read `$GC_RIG` at startup; exit immediately when it is empty (the HQ/global
  scope is a no-op for this watchdog).
- Remove the all-rigs `while ... read` loop; operate only on the single rig
  provided by the controller.
- Key the ledger filename by rig name
  (`rig-liveness-incidents-<rig-slug>.json`) so concurrent rig scopes each
  write their own file and never contend.

The result is exactly one effective invocation per rig, driven by the
controller's existing fan-out, with zero global duplicate.

---

## Bug 2 — Merge-stall false positives on sleeping dev rigs

**Root cause.** On a low-activity dev rig the refinery legitimately idles for
hours: it picks up a single merge bead, completes it, and then sleeps until the
next bead arrives. During that sleep the bead assigned to the refinery can sit
stale long past `$WATCHDOG_FRESH_MIN` minutes. The previous logic treated any
non-empty queue + no recent merge as an unconditional stall and fired an
`[INCIDENT]` escalation. This produced false positives every night on any city
with a quiet dev rig.

**Fix.** Distinguish idle from stalled by gating the merge-stall alert on a
*real* backlog:

- Add `WATCHDOG_MIN_QUEUE` (default `2`): a merge-stall fires only when the
  merge queue holds at least this many beads **or** there are actual unmerged
  feature branches waiting on the rig's default branch.
- A lone stale bead with no unmerged branches is treated as idle/quiet, not
  stalled.
- A dead or crashed refinery (hard-dead session state) remains an unconditional
  incident regardless of queue depth — a crashed refinery is never normal idle.

---

## Additional changes in this PR

- **Role names are now env-configurable.** The jq session-matching selectors no
  longer hard-code `refinery` and `witness`. Set `WATCHDOG_REFINERY_ROLE` and
  `WATCHDOG_WITNESS_ROLE` on the controller env to override (defaults: `refinery`,
  `witness`).

- **`WATCHDOG_ESCALATE_TO` is now required.** There is no longer a default of
  `"mayor"`. The script exits 1 with a stderr message if this var is unset,
  forcing the consumer to declare the recipient explicitly.

- **`gc bd list --rig` dependency.** The queue check uses `gc bd list --rig
  <rig>` which requires the version of `gc` that added per-rig bd scoping. A
  comment in the script documents this dependency.

## Files changed

| File | Change |
|---|---|
| `maintenance/assets/scripts/rig-liveness-watchdog.sh` | Rig-scope guard, per-rig ledger, `WATCHDOG_MIN_QUEUE` gating, configurable role vars, required `WATCHDOG_ESCALATE_TO` |
| `maintenance/orders/rig-liveness-watchdog.toml` | In-file docs updated to reflect real-backlog gating; `scope` left unset (rig-scoped default) |

## Testing

Run the watchdog with `GC_RIG=""` and confirm it exits 0 immediately (global
no-op). Run with `GC_RIG=<rig>` and confirm it checks only that rig and writes
`rig-liveness-incidents-<rig>.json`. Confirm that a refinery with a single
stale bead and no unmerged branches does not fire an incident when
`WATCHDOG_MIN_QUEUE=2`.
