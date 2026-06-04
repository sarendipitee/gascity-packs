# fix(deacon): add bug-filing routing rules and no-idle-cycle enforcement

## Summary

This PR fixes two independent behavioral bugs in the deacon prompt that surface in production Gas Town deployments.

---

## Problem 1: Bugs filed to the wrong polecat pool

The deacon's patrol cycle discovers bugs and infrastructure issues. Without explicit routing guidance, deacon agents were routing all bugs to whatever polecat pool was available — including rig-scoped polecats (e.g. `my-rig/gastown.polecat`) for gastown infrastructure bugs. A rig-scoped polecat operates inside a single git worktree and has no access to the gastown/gc source tree. It claims the bead, spins its wheels, and either stalls or produces incorrect output.

**Fix:** Added an explicit routing table and decision rule to the prompt:

- Rig-specific bugs → `gc bd create --rig <rig>` + sling to that rig's polecat
- Gastown infrastructure bugs → `gc bd create --rig gastown` + mail mayor for triage
- Cross-rig / unclear → HQ bead + mail mayor

The guiding heuristic is "which git repo would the fix land in?" — file there. The prompt also now explicitly prohibits setting `gc.routed_to` for anything that needs mayor triage, because a wrong pool assignment is worse than an empty one.

---

## Problem 2: Deacon enters idle state between patrol cycles

After completing a patrol cycle, the `next-iteration` formula step pours the next `mol-deacon-patrol` wisp and assigns it to the deacon before burning the current one. However, without explicit instruction to run `gc hook` immediately, deacon agents would emit the phrase "Standing by for the next hook" and wait passively — effectively halting the patrol loop until manually nudged.

**Fix:** Added a "No Idle State Between Cycles" section that:

1. Instructs the deacon to run `gc hook` immediately after `next-iteration` completes
2. Flags "Standing by for the next hook" as a bug indicator
3. Provides a crash-recovery bash snippet for the edge case where the deacon exited a cycle without running `next-iteration` (e.g. context exhaustion mid-formula) — it pours a fresh wisp, assigns it, and burns the stale one before calling `gc hook`

---

## Why upstream users hit this

Any Gas Town deployment running a deacon patrol loop will encounter both issues:

- **Routing bug:** surfaces as soon as the deacon files its first infrastructure or ambiguous bug — easy to miss initially because the bead appears to be handled, but the assigned polecat makes no progress.
- **Idle cycle bug:** surfaces on every patrol cycle completion — the deacon goes passive and requires an operator or mayor to nudge it back into the loop. High-frequency patrols (every few minutes) make this extremely disruptive.

Neither fix introduces new primitives or changes any Go code. Both are purely prompt-level behavioral corrections in `gastown/agents/deacon/prompt.template.md`.

---

## Files changed

- `gastown/agents/deacon/prompt.template.md` — 80 lines added, 1 line changed
