# gascity-jj-base Live JJ Review

Schema: `gc.build.review.v1`
Source change: `wwppnzmw` (`a62e1259`)
Source workspace path: `/data/projects/doltlite-gascity/gascity-packs`
Review change: `ypryqolw`

## Verdict

Changes required.

## Findings

1. **P1 - `jj-review` routes `write-report` after validation records a blocking context failure**

   `gascity-jj-base/formulas/jj-review.formula.toml:41` defines the
   `validate-context` step, and `gascity-jj-base/formulas/jj-review.formula.toml:56`
   makes `write-report` depend only on that step closing. The validation prompt
   says missing manifest, unreadable document paths, missing schemas, missing
   hashes, and missing change IDs are blocking context issues
   (`gascity-jj-base/assets/workflows/jj-docs/validate-review-context.md:7` and
   `gascity-jj-base/assets/workflows/jj-docs/validate-review-context.md:12`),
   while the report prompt requires loading `{{manifest_path}}` before writing
   the review (`gascity-jj-base/assets/workflows/jj-docs/review-document.md:7`).

   This live workflow reproduced the gap: `gp-d9id` closed with
   `gc.context_verdict=blocked` and
   `gc.context_blocking_reason=manifest missing; no manifest schema/hash/document paths readable; subject source change differs from workflow source change`,
   but `gp-22cp` was still routed and asked to load the missing manifest.
   That defeats the manifest-as-source-of-truth contract and pushes a known bad
   context into the report writer.

   Fix: make a blocked validation result stop the review lane before
   `describe-review-report-change` or `write-report` can run. Either have the
   validation worker close blocking context as `gc.outcome=fail`, or add a
   graph check/scope-check that gates those downstream steps on a ready verdict.
   Add a regression test that constructs a missing-manifest validation result
   and asserts `write-report` is not made ready.

## Verification

- Confirmed `default@` is the document workspace and `@` was already described
  as `gascity-jj-base: write jj review report` before writing this file.
- Confirmed `/data/projects/doltlite-gascity/gascity-packs` is a jj workspace
  and inspected source change `wwppnzmw` there.
- Inspected the `jj-review` formula and the validate/review workflow prompts at
  `wwppnzmw`.
- Confirmed the new tests cover workspace metadata and describe-step ordering,
  but do not cover validation blocking the downstream report step.

## Context Notes

- The configured manifest path was missing at review start:
  `/data/projects/doltlite-gascity/gascity-packs/gascity-jj-base/reviews/live-test-2026-06-22-jj-review/manifest.json`.
- This report creates that manifest only to satisfy the document artifact
  contract for the review result; the finding above is based on the pre-existing
  blocked validation state.
