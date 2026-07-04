{{ define "jjw-workspace-reporting" -}}
## jjw Workspace Reporting

Use the `jjw` workspace report to inspect the rig's managed workspaces without
guessing from repository layout.

Preferred entry points:

- `gc jjw workspace-report`
- `jjw/assets/scripts/workspace-report.sh`
- formula `mol-jjw-workspace-report`
- order `jjw-workspace-report`

The report should include `jjw version` and `jjw list --verbose` output. When a
formula step appends a report to a bead, append the report as notes on the
claimed work bead rather than creating a synthetic tracking bead.
{{- end }}
