# Generate JJ-Managed Root Task Stage Report

Produce or update the `root-task-stage-report` document.

Required behavior:

- Keep the generated report under the default@ document workspace. Do not write
  the canonical report to `.gc/reports`.
- Read `gc.docs.artifact_root` and `gc.docs.manifest_path` from the workflow
  root bead metadata or from `{{docs_artifact_root}}` and `{{manifest_path}}`.
- If `{{report_path}}` is empty, write
  `<docs_artifact_root>/root-task-stage-report.md`.
- Resolve `{{script_path}}` from the document workspace. If the current
  directory is the `gascity-packs` checkout, the default script path is already
  correct.
- Run the generator with the resolved paths:

```bash
node {{script_path}} \
  --city-root <city-root> \
  --docs-workspace {{docs_workspace}} \
  --docs-workspace-path <docs-workspace-path> \
  --docs-artifact-root <docs-artifact-root> \
  --manifest <manifest-path> \
  --output <report-path>
```

- If `{{rigs}}` is non-empty, pass `--rigs "{{rigs}}"`.
- If `{{include_wisps}}` is `true`, pass `--include-wisps`.
- If `{{include_workflow_metadata}}` is `true`, pass
  `--include-workflow-metadata`.
- Confirm the report includes the `Stage` column.
- Confirm the report and manifest are tracked in the JJ document workspace
  (`jj file list -r @` should include both paths, or run `jj file track` for
  those concrete files).
- Update bead metadata via the manifest path and per-document keys:
  `gc.docs.root-task-stage-report.path`,
  `gc.docs.root-task-stage-report.schema`,
  `gc.docs.root-task-stage-report.hash`, and
  `gc.docs.root-task-stage-report.change_id`.

Keep the report body in the JJ workspace. Put only paths, schemas, hashes, and
change IDs in bead metadata or comments.
