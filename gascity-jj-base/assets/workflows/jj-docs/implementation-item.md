# Implement JJ Work Item

Implement the assigned work item and write a manifest-managed implementation
summary.

Required behavior:

- Use `gc.docs.source_workspace_path` for source edits, source tests, and source
  jj commands. Hard-stop if the path is missing or is not a jj workspace; do not
  fall back to `default@` for source edits.
- Do not create or select a new jj workspace in this step.
- Confirm the preceding describe step has described the source jj change that
  will receive these edits. Do not edit source files from an undescribed `@`.
- Use `{{manifest_path}}` to read requirements, plan, decomposition, and any
  prior review/fix documents.
- Write or update the implementation summary at the path selected by
  `gc.docs.document_path_keys`.
- Include both source and document identities in the summary:
  source workspace, source change ID, default@ artifact root, document path,
  hash, and document change ID.
- Update `manifest.json`, the claimed step bead, and the workflow root bead with
  the implementation summary path, schema, SHA-256 content hash, and jj document
  change ID. Use `gc.docs.implementation-summary.path`,
  `gc.docs.implementation-summary.schema`,
  `gc.docs.implementation-summary.hash`, and
  `gc.docs.implementation-summary.change_id`.
- Record the latest source change ID on `gc.docs.source_change_id`.
- If `.gc/scripts/checks/build-artifact-valid.sh` is available from the
  launcher rig root, validate the claimed step with
  `GC_BEAD_ID=<claimed-step-id> .gc/scripts/checks/build-artifact-valid.sh`
  and fix every reported issue before closing.
- When the source fixes, summary, manifest, and bead metadata are complete, set
  `gc.outcome=pass` on the claimed step with `bd update`, then close it with
  `bd close <claimed-step-id> --reason "<concise reason>"`. Do not pass
  `--metadata` or `--set-metadata` to `bd close`.

Do not rely on prompt context as the durable implementation record.
