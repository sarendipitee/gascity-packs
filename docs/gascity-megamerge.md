# Gas City Megamerge

Gas City megamerge work uses Jujutsu's multi-parent merge workflow to repair
several related lines at once without losing which line should own each fix.

This is useful when history already contains partial or broken fixes spread
across several changes. Create one merge commit with every relevant line as a
parent, then create an empty child above it as the scratch working commit. Work
in the child, and route finished hunks back into the owning lines with
`jj absorb`, `jj squash --from ... --into ...`, or `jj-hunk`.

## Shape

```text
@  scratch child
o  merge: reconcile related lines
|\
| o line: native writes
| o line: write locking
| o line: metadata preservation
o  current integration base
```

The merge commit is the integrated view. The child is temporary scratch space.
Do not copy the resolved files to an unrelated linear branch; that breaks the
benefit of simultaneous editing.

## Workflow

1. Identify the lines that contain related work:

   ```bash
   jj log -r 'present(@) | ancestors(immutable_heads().., 2) | present(trunk())'
   jj log -r 'description("doltlite") | description("native") | description("wisp")'
   ```

2. Create the megamerge:

   ```bash
   jj new <line-a> <line-b> <line-c> <current-base> -m "merge: reconcile <topic>"
   ```

3. Resolve conflicts in the merge until the integrated view builds.

4. Create the scratch child:

   ```bash
   jj new @ -m "wip: continue <topic> reconciliation"
   ```

5. Make new fixes only in the scratch child.

6. Route hunks back into their owning lines:

   ```bash
   jj absorb
   jj-hunk list -r @ --format text
   jj squash --from @ --into <owning-line> -m "fix: <owned behavior>"
   ```

   Prefer `jj-hunk` when only some hunks in a file belong to a line.

7. Keep the merge commit as the validation surface. Run the build and focused
   tests from the scratch child or the merge.

8. When a parent line is fully superseded, abandon it only after its useful
   hunks have been absorbed into the surviving line.

## Ownership

Assign every hunk to a line before routing it:

- build or fast-path plumbing belongs to the line that introduced that plumbing
- locking belongs to the write-serialization line
- metadata merge behavior belongs to the metadata-preservation line
- native write helpers belong to the native-write line
- tests go with the behavior they protect

If ownership is ambiguous, leave the hunk in the scratch child and document the
question in the bead rather than guessing.

## Checks

Run a build first:

```bash
go build ./cmd/gc
```

Then run focused tests for the integrated area. Example for DoltLite beads:

```bash
CGO_ENABLED=1 go test -tags gascity_doltlite_lib ./internal/beads -run 'TestDoltliteReadStore' -count=1 -timeout=120s
```

Before handing off, show:

```bash
jj log -r 'present(@) | parents(@) | parents(@-)'
jj status
jj diff --git --from <integration-base> --to @-
```
