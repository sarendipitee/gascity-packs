# Review JJ-Managed Document

Review the current workflow state using the manifest as the source of truth.

Required behavior:

- Load `{{manifest_path}}` and follow document paths from the manifest instead
  of relying on pasted prompt context.
- Confirm the preceding describe step has described the jj change that will
  receive this review document. Do not write review files from an undescribed
  `@`.
- If `{{source_change_id}}` is present, review the source state identified by
  that jj change ID together with the relevant document set.
- Use `gc.docs.source_workspace_path` for source inspection. Hard-stop if the
  source path is missing or is not a jj workspace; do not inspect source state
  from `default@` unless the recorded source workspace path is explicitly the
  default workspace checkout.
- Write the review artifact to the path identified by
  `gc.docs.document_path_keys` or `gc.build.artifact_path_keys`.
- Update `manifest.json` with the review path, schema, hash, and jj document
  change ID.
- Record `gc.docs.review.path`, `gc.docs.review.schema`,
  `gc.docs.review.hash`, `gc.docs.review.change_id`, and the latest
  `gc.docs.change_id` on the workflow root bead.

The review can summarize findings in the bead, but the full report remains a
tracked document file.
