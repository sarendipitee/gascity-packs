# Formula Improvement Plan

## Goal

`gascity-jj-base` extends the upstream `gascity` base pack with jj-native
document behavior.

The live bead database remains DoltLite. Workflow documents are normal files in
the `default@` checkout. Formula steps pass document references by path, schema,
content hash, and jj change ID instead of relying on prompt context or bead
metadata alone.

## Core Runtime Model

Each workflow root gets an artifact root under the `default@` checkout:

```text
plans/<root-bead-id>/
  manifest.json
  requirements.md
  implementation-plan.md
  plan-review.md
  decomposition.md
  implementation-summary.md
  review.md
  qa.md
  release-readiness.md
  final-report.md
  root-task-stage-report.md
```

The workflow root bead records:

```text
gc.docs.workspace=default
gc.docs.workspace_path=<absolute path to default@ checkout>
gc.docs.base_revset=default@
gc.docs.artifact_root=<default@ checkout>/plans/<root-bead-id>
gc.docs.manifest_path=<artifact_root>/manifest.json
gc.docs.change_id=<jj change id containing the latest document state>
```

Each document-producing step records document metadata:

```text
gc.docs.<name>.path=<absolute path>
gc.docs.<name>.schema=<schema id>
gc.docs.<name>.hash=sha256:<digest>
gc.docs.<name>.change_id=<jj change id>
```

## Document Manifest

`manifest.json` should be the stable handoff surface. Downstream steps read it
to discover documents instead of re-deriving paths.

Suggested shape:

```json
{
  "root_bead_id": "gc-123",
  "workspace": "default",
  "base_revset": "default@",
  "artifact_root": "plans/gc-123",
  "documents": {
    "requirements": {
      "path": "plans/gc-123/requirements.md",
      "schema": "gc.build.requirements.v1",
      "hash": "sha256:...",
      "change_id": "..."
    }
  }
}
```

The manifest is deliberately small enough for bead metadata to point at it, but
large enough that agents do not need every prior document pasted into their
prompt.

## Formula Extensions

### `jj-build`

Extends `build-base`.

Overrides `prepare` to:

- resolve the workflow document owner as the `default@` checkout
- set `artifact_root` to the default checkout's run directory
- write `manifest.json`
- record `gc.docs.*` metadata on the workflow root bead

Keeps the inherited base stage order. Methodology packs such as BMAD and gstack
can later extend this instead of `build-base`, or a wrapper can pin selector
vars while leaving their methodology formulas unchanged.

### `jj-planning-base`

Extends `planning-base`.

Improves `requirements`, `plan`, and `plan-review` handoffs by requiring each
step to:

- read existing inputs from `manifest.json`
- write its output under the `default@` artifact root
- update `manifest.json`
- record path, schema, hash, and change ID on the workflow root bead

This avoids passing large requirements and plan bodies through prompt context
when a stable path is enough.

### `jj-decomposition-base`

Extends `decomposition-base`.

Writes the decomposition artifact under the `default@` artifact root and stores the
source document references on every created work bead:

```text
gc.docs.manifest_path
gc.docs.requirements.path
gc.docs.plan.path
gc.docs.decomposition.path
```

Implementation beads should receive document pointers, not copied document
text.

### `jj-implement`

Extends `implement`.

Keeps the Gas City drain lifecycle but makes source and document identity
explicit:

- source code work happens in source jj workspaces
- workflow evidence is written under the `default@` artifact root
- the root implementation summary is written after fanin from child item
  summaries

For `drain_policy=separate`, do not let parallel agents write the same document
file. Use per-item artifact subdirectories and an integration step.

### `jj-do-work`

Extends `do-work`.

Used by separate-drain implementation items. Each item should have:

- one source jj workspace for code changes
- one item-scoped artifact subdirectory under the `default@` artifact root
- an implementation summary written to the item document path

On success, the item records:

```text
gc.source.change_id=<source jj change id>
gc.docs.item_summary.path=<path>
gc.docs.item_summary.change_id=<doc jj change id>
```

### `jj-do-work-item`

Extends `do-work-item`.

Used by same-session drains. Because work is serialized, it may share the root
artifact directory safely. It should still write item-scoped summaries and
record the same `gc.source.*` and `gc.docs.*` fields as `jj-do-work`.

### `jj-review`

Extends `code-review-base`.

Review steps should consume document paths and source change IDs:

- requirements path
- plan path
- decomposition path
- implementation summary path
- source jj change IDs or revsets

The review report is written under the `default@` artifact root and recorded in
`manifest.json`.

### `jj-fix-loop`

Extends `fix-loop-base`.

Review fixes should preserve the existing document references while adding:

- fix source change ID
- updated item summary path
- updated review report path
- iteration number

### `root-task-stage-report`

Report-only formula for the city-wide active root task stage summary.

Writes `root-task-stage-report.md` under the `default@` artifact root and
updates `manifest.json` with the report path, `gc.reports.root-task-stage.v1`
schema, SHA-256 hash, and document jj change ID. The canonical report must not
be written only to `.gc/reports`, because `.gc` is local runtime state rather
than the durable document handoff surface.

### `jj-publish`

Extends or wraps `publish`.

Publish should be explicit about jj semantics:

- bookmarks are moved intentionally
- `jj git push` is used for source publication
- PR creation passes `--head <bookmark>`
- document publication is separate from source publication unless the
  caller opts into publishing workflow evidence

## Parallel Document Policy

The important jj-specific improvement is avoiding concurrent writes to one file.

Recommended policy:

| Workflow shape | Source workspace | Document location |
| --- | --- | --- |
| Planning | root run workspace | `default@` artifact root |
| Separate implementation drain | one per item | item subdirectory, then integrate |
| Same-session implementation drain | shared serialized source lane | `default@` artifact root |
| Review fanout | read-only source refs | one review context, fanout findings in separate files |
| Fix loop | implementation target source workspace | iteration-scoped document files |

The document fanin step updates `manifest.json` and records the final document
change ID on the workflow root bead.

## Initial Formula Surface

The first implementation pass adds these formulas and shared `jj-docs` workflow
assets:

- `jj-build`
- `jj-planning-base`
- `jj-decomposition-base`
- `jj-implement`
- `jj-do-work`
- `jj-do-work-item`
- `jj-review`
- `jj-fix-loop`
- `jj-publish`

The formulas are intentionally thin. They extend upstream `gascity` formulas,
add default@ document variables/metadata, and override only the steps that need
manifest-aware handoff or jj-specific drain routing.

## Follow-up Runtime Work

Harden these behaviors in order:

1. Implement the `prepare` runtime helper that resolves the default@ checkout,
   artifact root, and manifest.
2. Add manifest update helpers for requirements, plans, decomposition,
   implementation summaries, reviews, and final reports.
3. Teach drains to pass document variables to item formulas.
4. Record source workspace/change IDs consistently from implementation workers.
5. Add publish helpers after the document/source separation is proven.

This keeps the extension pack thin while letting BMAD, gstack, and future
methodology packs inherit jj-native document handling through selector vars
rather than copying their formula graphs.
