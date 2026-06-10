# feat(maintenance): watchdog catches asleep-too-long (stalled) witness loop

## The Gap

The rig-liveness watchdog already caught **dead** sessions — states like
`crashed`, `failed-create`, or `closed`. But there is a second, more
insidious failure mode: a witness that is in an `asleep` or `active` state
whose **self-scheduled patrol loop has silently died**.

The witness's ScheduleWakeup loop is responsible for periodically waking the
agent to check for pending work. When this loop dies, the witness sits
`asleep` indefinitely — its session state looks healthy but it is patrolling
nothing. The existing dead-state check cannot see this because the session is
not dead.

## Evidence

This failure was observed in production. Specific patrol stalls of **14 hours
to 63 hours** were recorded, all while the witness session reported an
`asleep` or `active` state throughout. Work accumulated silently; no alert
fired.

A healthy witness wakes approximately every 60 seconds between patrol cycles.
Fifteen minutes of silence is therefore a clear signal that the loop is gone —
not a transient sleep. The threshold is configurable via
`WATCHDOG_WITNESS_STALE_MIN` (default: 15 minutes).

## The Fix

**Heartbeat freshness check (Check 1b)** added to `rig-liveness-watchdog.sh`:

After the existing dead-state check passes (witness is alive), the watchdog
now reads the witness session's `last_active` and `last_nudge_delivered_at`
fields and takes the newer of the two as the heartbeat. The
`last_nudge_delivered_at` field is particularly useful here because the patrol
loop's self-nudge mechanism keeps it fresh every cycle.

If the heartbeat is more than `WATCHDOG_WITNESS_STALE_MIN` minutes old — and
the field is not the Go zero-time sentinel (see below) — the watchdog emits a
`:witness:stalled` incident.

The new incident is a **distinct class** from `:witness:dead`. This matters
because the de-duplication ledger tracks incidents by key
(`rig:agent:symptom-class`). A session could transition from stalled to dead
in subsequent ticks; keeping these as separate keys prevents de-dup logic from
treating one as a continuation of the other and suppressing the re-alert.

## Go Zero-Time Sentinel Handling

`gc` emits `0001-01-01T00:00:00Z` for any session field that has not been set
yet (the Go zero value for `time.Time`). The new `ts_epoch()` helper treats
this value — and any timestamp beginning with `0001-` — as "no usable signal"
(returns `0`), never as "ancient". A zero epoch skips the staleness check
entirely, avoiding false positives on newly-started witnesses that have not yet
recorded a heartbeat.

## Why Refinery Staleness Was Not Added

Refinery heartbeat freshness was deliberately **not** added:

1. When a merge queue is non-empty, the refinery merge-freshness check (Check
   2) already catches a stalled refinery.
2. When the merge queue is empty, a non-nudged refinery is legitimately idle —
   a heartbeat-age check would false-alert.

Adding refinery staleness would duplicate the merge-stall check on the busy
path and add false positives on the idle path. No net gain.

## Configuration

All thresholds are env-overridable. `WATCHDOG_ESCALATE_TO` is **required** —
it has no default and the script exits with an error if unset. Set it in your
pack config to the agent role that should receive incident mail (e.g. your
overseer). This keeps the script free of hardcoded role names.

| Variable | Default | Description |
|---|---|---|
| `WATCHDOG_WITNESS_STALE_MIN` | `15` | Minutes of silence before a live witness is flagged stalled |
| `WATCHDOG_ESCALATE_TO` | *(required — no default)* | Recipient for `[INCIDENT]` mail; must be set by consumer pack config |
| `WATCHDOG_FRESH_MIN` | `60` | Refinery merge-freshness window |
| `WATCHDOG_REALERT_TICKS` | `5` | Re-alert cadence per persistent incident |

## Portability

`ts_epoch()` tries GNU `date -d` first, then BSD `date -j -f` as a fallback,
so the stall-detection logic works correctly on both Linux and macOS/BSD
systems.

## Incident Format

Emitted as a `[INCIDENT]` mail to `$WATCHDOG_ESCALATE_TO` with full evidence:
rig name, witness state, last heartbeat age, and suggested remediation action.
The de-dup ledger ensures a persistent stall does not spam every tick.
