---
name: gascity-megamerger
description: Use for Gas City megamerger work: Jujutsu megamerge repairs across several related jj lines, multi-parent merge workbenches, scratch children, hunk routing with jj-hunk, and cleaning up incomplete or duplicate repair lines.
---

# Gas City Megamerger

Use this skill when the Gas City megamerger is repairing several related
Jujutsu lines at once.

## Core Pattern

1. Identify every related line.
2. Name the current head revision for each line that must be tested together.
3. Create or restage a multi-parent merge with those stack heads as parents.
4. Prove every intended stack head is an ancestor of the merge.
5. Resolve that merge until the integrated view makes sense.
6. Create an empty scratch child above the merge.
7. Make new fixes in the scratch child.
8. Route hunks back into the owning parent line.
9. Keep the merge as the integrated validation surface.

Do not copy the final files to an unrelated linear branch. That loses the
connection between the fix and the line that should own it.

Do not trust graph proximity. A stack shown near the megamerge is not included
unless its head is in `::<megamerge>`.

## Commands

Create the merge:

```bash
jj new <line-a> <line-b> <line-c> -m "merge: reconcile <topic>"
```

Restage a merge when a stack is missing:

```bash
jj new <existing-parent-a> <existing-parent-b> <missing-stack-head> -m "merge: reconcile <topic>"
```

Create the scratch child:

```bash
jj new @ -m "wip: continue <topic> reconciliation"
```

Prove membership:

```bash
jj log --no-pager -r '<stack-head> & ::<megamerge>'
jj log --no-pager -r '<megamerge> & <stack-head>::'
jj log --no-pager -r '<megamerge>-'
```

The first command must print the stack head. If it does not, restage the
megamerge before repairing or verifying.

Inspect ownership:

```bash
jj log --no-pager -r 'present(@) | parents(@) | parents(@-)'
jj diff --git --no-pager --from <base-line> --to @-
jj-hunk list -r @ --format text
```

Route work:

```bash
jj absorb
jj squash --from @ --into <owning-line> -m "fix: <owned behavior>"
```

Use `jj-hunk` when only selected hunks belong to an owning line.

## Ownership Rules

- Build and fast-path plumbing belongs to the line that introduced that
  plumbing.
- Write locking belongs to the write-serialization line.
- Metadata merge logic belongs to the metadata-preservation line.
- Native create/update/delete/dependency code belongs to the native-write line.
- Tests should move with the behavior they protect.

## Verification

Always run a build or focused test from the integrated view:

```bash
go build ./cmd/gc
```

For DoltLite bead work:

```bash
CGO_ENABLED=1 go test -tags gascity_doltlite_lib ./internal/beads -run 'TestDoltliteReadStore' -count=1 -timeout=120s
```

## Handoff

Report:

- merge change id
- scratch child change id
- parent stack heads and their intended ownership
- membership proof for every intended stack head
- build/test commands run
- remaining duplicate or obsolete lines
