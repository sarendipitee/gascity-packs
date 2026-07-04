# Record JJ Source Anchor

After implementation, record the source identity that downstream formulas should
review or publish.

Required behavior:

- Determine the latest source jj change ID for the implementation item.
- Record it on the item bead and workflow root bead as
  `gc.docs.source_change_id`.
- Record the source workspace as `gc.docs.source_workspace`.
- Record the source workspace path as `gc.docs.source_workspace_path`.
- Update `manifest.json` with the source workspace/change ID association.
- Confirm the implementation summary document exists and its manifest entry has
  a path, schema, hash, and document change ID.

This step closes the implementation item's source/document handoff.
