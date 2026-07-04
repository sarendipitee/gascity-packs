# Plan JJ Review Fixes

Turn review findings into a concrete fix plan using stable source and document
identities.

Required behavior:

- Read review findings from `{{manifest_path}}` or `{{findings_path}}`.
- Confirm the preceding describe step has described the jj change that will
  receive the fix plan or source fix edits.
- Reference the source workspace and source change ID that need fixes.
- Produce fix instructions that preserve the manifest handoff for
  implementation and re-review.
- Record any new fix-plan document path, hash, schema, and document change ID in
  the manifest when a file is produced.

Downstream fix application should update source change IDs and manifest entries
before re-review.
