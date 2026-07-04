# gascity-jj-base Sling Review Fix Plan

Schema: `gc.review.fix-plan.v1`
Source workspace: `gascity-packs`
Source workspace path: `/data/projects/doltlite-gascity/gascity-packs`
Source change: `tynmlvxmoqkw` (`a8e075e1dc58`)
Review document: `gascity-jj-base/reviews/pack-review-2026-06-22-sling/review.md`
Review change: `xylxutzm`
Fix-plan document change: `twxnwoow`

## Intent

Apply the single P2 review finding: the `jj-fix-loop` document-scoped describe
steps must carry the document workspace metadata required by
`describe-jj-change.md`.

## Required Source Fix

Update `gascity-jj-base/formulas/jj-fix-loop.formula.toml`:

- In step `describe-fix-plan-change`, add:
  - `gc.docs.workspace_key = "gc.docs.workspace,gc.var.docs_workspace"`
  - `gc.docs.workspace_path_key = "gc.docs.workspace_path,gc.var.docs_workspace_path"`
- In step `describe-re-review-change`, add the same two metadata keys.

Preserve the existing `gc.docs.manifest_path_keys` and
`gc.docs.source_change_id_key` metadata. Do not change the source-scoped
`describe-source-fix-change` step; it already uses source workspace metadata.

## Required Regression Test

Extend `gascity-jj-base/tests/test_gascity_jj_base_pack.py`, preferably in or
next to `test_every_formula_has_concrete_describe_step`, so every describe step
with `gc.jj.describe_scope == "document"` must declare:

- `gc.docs.workspace_key`
- `gc.docs.workspace_path_key`

Assert the canonical values exactly:

- `gc.docs.workspace,gc.var.docs_workspace`
- `gc.docs.workspace_path,gc.var.docs_workspace_path`

The test should fail on the current `jj-fix-loop.formula.toml` before the
formula metadata is patched, and pass after both document-scoped describe steps
are fixed.

## Verification

Run the focused pack test:

```bash
pytest -q gascity-jj-base/tests/test_gascity_jj_base_pack.py
```

## Manifest Handoff

Keep the manifest at
`gascity-jj-base/reviews/pack-review-2026-06-22-sling/manifest.json` as the
handoff document. Downstream fix application should update the manifest source
change metadata after the source fix is applied, and re-review should append or
update the review document metadata without removing this fix-plan entry.
