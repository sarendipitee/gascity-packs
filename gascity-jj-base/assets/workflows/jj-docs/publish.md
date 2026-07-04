# Publish JJ Workflow Result

Publish only after source and document state are identifiable.

Required behavior:

- Read the final report and source identity from `{{manifest_path}}`.
- Confirm the latest source change ID is known before pushing or opening a PR.
- Confirm `gc.docs.source_workspace_path` resolves to the jj workspace that owns
  that source change ID. Hard-stop instead of publishing from `default@` when the
  recorded source workspace path is missing or different.
- Confirm the source change being published is already described. If publication
  needs to update the current source change description, do that before pushing
  or opening a PR.
- Confirm the default@ artifact root has the final manifest state.
- If `{{push}}` is enabled, move/push the appropriate jj-backed Git bookmark for
  the source change.
- If `{{open_pr}}` is enabled, open or update the PR from the pushed bookmark.
- Leave the document manifest path and latest document change ID on the workflow
  root bead for debugging.

Do not publish based on an unrecorded source checkout or prompt-only final
report.
