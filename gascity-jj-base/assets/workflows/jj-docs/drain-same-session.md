# Drain JJ Work In One Shared Session

Drain implementation work in the current session while preserving document
handoff.

Required behavior:

- Pass `docs_workspace`, `docs_workspace_path`, `docs_artifact_root`, and
  `manifest_path` to the item formula.
- Keep shared-session item work serial.
- Write each implementation summary as a manifest-managed document.
- Update `manifest.json` after each item so later items can consume current
  document state.

The drain formula for this step must be `jj-do-work-item`.
