# Drain JJ Work In Separate Sessions

Drain implementation work into separate sessions while preserving document
handoff.

Required behavior:

- Pass `docs_workspace`, `docs_workspace_path`, `docs_artifact_root`, and
  `manifest_path` to each item formula.
- Separate sessions are execution lanes, not source workspace identities. Pass
  any known source workspace, source workspace path, and source change ID to
  each item formula so workers reuse the prepared source lane.
- Ensure each worker writes its implementation summary as a manifest-managed
  document.
- For parallel writers, use item-scoped document paths or item-scoped document
  workspaces, then let the coordinating formula integrate them into the root
  manifest.
- Create a child source workspace only when `gc.pack_workspace` is explicitly
  present or the manifest already names one. Do not derive child source
  workspaces from formula names, step IDs, step bead IDs, attempts, or generated
  session names.

The drain formula for this step must be `jj-do-work`.
