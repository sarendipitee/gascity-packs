{{ define "packrouter-workspace-routing-examples" -}}
Default reusable workspace: use this for ordinary implementation work that can
continue in `.gc/workspaces/<rig>/packs/<pack>`. Omit workspace flags.

```bash
packer/assets/scripts/create-pack-bead.sh \
  --parent gp-rte \
  --pack jj-hunk \
  --pack-root jj-hunk \
  --title "jj-hunk: add hunk preview formula" \
  --description "Add a formula that previews selected jj diff hunks." \
  --acceptance "gc lint jj-hunk passes"
```

Named workspace reuse: use this when `list-pack-workspaces.sh` shows an
existing named workspace carrying the change that should receive follow-up
work.

```bash
packer/assets/scripts/create-pack-bead.sh \
  --parent gp-rte \
  --pack jj-hunk \
  --pack-root jj-hunk \
  --workspace review-fixes \
  --title "jj-hunk: address review follow-up" \
  --description "Continue the review-fixes workspace and tighten hunk parsing." \
  --acceptance "gc lint jj-hunk passes"
```

Isolated task workspace: use this when the task should not share the default or
an existing named workspace, such as risky parallel work or a change that needs
its own continuation lane.

```bash
packer/assets/scripts/create-pack-bead.sh \
  --parent gp-rte \
  --pack jj-hunk \
  --pack-root jj-hunk \
  --task-workspace \
  --title "jj-hunk: prototype alternate hunk selector" \
  --description "Create an isolated task workspace for selector prototype work." \
  --acceptance "gc lint jj-hunk passes"
```
{{- end }}
