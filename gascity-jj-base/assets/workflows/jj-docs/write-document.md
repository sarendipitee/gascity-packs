# Write JJ-Managed Document

Produce or update the document named by step metadata `gc.docs.document`.

Required behavior:

- Read inputs from `{{manifest_path}}` whenever the manifest exists.
- Confirm the preceding describe step has described the jj change that will
  receive this document edit. Do not write document files from an undescribed
  `@`.
- Write the output as a normal file under the default@ artifact root, preferably
  under `{{docs_artifact_root}}`.
- Use the path keys in `gc.docs.document_path_keys` and
  `gc.build.artifact_path_keys` to choose and record the canonical path.
- Validate the document against `gc.build.artifact_schema` when that metadata is
  present.
- Update `manifest.json` with the document path, schema, SHA-256 content hash,
  and jj document change ID.
- Record per-document bead metadata:
  `gc.docs.<name>.path`, `gc.docs.<name>.schema`,
  `gc.docs.<name>.hash`, and `gc.docs.<name>.change_id`.
- Record the workflow root's latest `gc.docs.change_id`.

Keep the document body in the jj workspace. Put only paths, schemas, hashes, and
change IDs in bead metadata or comments.
