{{ define "lazyjj-workspace-refresh" }}
## LazyJJ Workspace Refresh Rule

LazyJJ workspaces must start from the current local integration view so agents
do not inspect stale work or fix problems that are already fixed.

- New worker workspace: start from `default@`.
- Existing empty worker workspace: move to a new empty child of `default@`.
- Existing non-empty worker stack: rebase the stack root onto `default@`; if
  that cannot be done cleanly, create a temporary megamerge with
  `jj new default@ worker-head -m "megamerge: inspect workspace refresh"` to
  inspect conflicts before deciding how to update the stack.
- Default workspace should not contain scratch edits; it is the integration
  baseline.
- The worker workspace and `default@` must not drift as independent valid
  heads; they should converge back to the same tested stack head before the
  next handoff.
- If either workspace has moved ahead on its own, use `jj rebase`, `jj edit`,
  or the cross-workspace sync formula to realign the graphs instead of copying
  files.

The workspace setup script enforces this before the agent session starts.
{{ end }}
