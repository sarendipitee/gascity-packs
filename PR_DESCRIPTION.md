# test(gastown): add pack content regression suite + CI

## Summary

Adds a standalone Go test module at `gastown/tests/` that validates the
gastown pack's file content as a pure regression suite, with no dependency
on the Gas City SDK. A new CI step runs it automatically on every push.

## What regressions the tests catch

The suite covers six categories of pack content:

**1. TOML validity** — Every `.toml` file in the pack is parsed; any
syntax error or schema drift fails the build. `pack.toml` structure
(name, schema version, import declarations) is locked to a specific shape.

**2. Formula correctness** — Refinery and Polecat formula steps are
tested for behavioral contracts: merge-strategy support, zero-diff guard,
existing-PR metadata handling, agent identity validation at startup,
wisp-burn successor gates, branch-shape gates, auto-push halt, and
cross-repo PR escalation. These tests prevent silent behavioral regressions
when formula shell scripts are edited.

**3. Prompt template content** — Prompt files are asserted to exist and
contain required sections (branch conventions, done-sequence signals,
CURRENT_WISP guards, rig-scope tokens, routing-namespace propagation, etc.).

**4. Worktree setup scripts** — The worktree bootstrap helpers are tested
for: pre-populated target dir handling, nested runtime tree setup, tracked
file preservation, legacy signature compatibility, agent-branch namespacing,
and origin-sync skip when no remote is configured.

**5. Role wiring / operational awareness** — Deacon patrol queue-starvation
detection, Witness patrol liveness/state-classification, refinery-patrol
restart guidance, polecat→refinery signal after reassign, and the
operational-awareness diagnostic fragment are all covered.

**6. Agent/rig config** — Rig-scoped shell tokens, rig-target shell
expressions (HQ and individual rig forms), and routing-namespace prefix
usage in `gc bd` commands are all locked.

## Why it's standalone

The test module lives at `gastown/tests/` with its own `go.mod`. It uses
only `stdlib` and `github.com/BurntSushi/toml` — no `internal/` SDK
packages are imported (Go module rules make that impossible anyway). This
means the tests have no Gas City SDK build dependency and can be run in
CI environments that do not have the SDK present. Note that several tests
invoke shell tools at runtime (git, jq, grep, sed, etc.), so those must be
available in the test environment.

## CI integration

The existing `.github/workflows/ci.yml` gains one step:

```yaml
- name: Run gastown pack content tests
  working-directory: gastown/tests
  run: go test ./...
```

It runs after the existing lint/validate steps and is scoped to the
`gastown/tests` directory.

`TestTmuxKeybindingsScrollWheel` is currently skipped — it documents a
genuine missing feature (WheelUpPane/WheelDownPane bindings, ga-c4w Part A)
and will be un-skipped once those bindings land in the upstream pack.
