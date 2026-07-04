# Prepare JJ Document Workspace

Resolve the workflow document location before any document-producing step runs.

Required behavior:

- Keep the live bead database in DoltLite.
- Use the default jj workspace for workflow documents:
  `docs_workspace=default`, `docs_base_revset={{docs_base_revset}}`.
- Resolve `{{docs_workspace_path}}` to the rig root/default@ checkout when it is
  empty.
- Resolve `{{docs_artifact_root}}` under that checkout. If it is empty, use a
  stable path under `plans/<workflow-root-bead-id>/`.
- Resolve or create `{{manifest_path}}` at
  `<docs_artifact_root>/manifest.json`.
- Ensure the manifest records the workflow root, default workspace, artifact
  root, base revset, and any already-known source workspace/change IDs.
- Record these values back on the workflow root bead:
  `gc.docs.workspace`, `gc.docs.workspace_path`, `gc.docs.base_revset`,
  `gc.docs.artifact_root`, `gc.docs.manifest_path`, and `gc.docs.change_id`.

Do not copy document bodies into bead notes. Beads should point at the manifest
and concrete document paths.
