
Use the mayor create beads procedure over approved requirements and the
implementation plan. In `interactive` mode, human-gate bead creation/start. In
`autonomous` mode, generate and approve `tasks.md`, then create the task beads
and implementation convoy non-interactively. Each issue-fix run owns one
generated implementation convoy; build-run fix convoys remain
iteration-specific. The `tasks.md` front matter must use
`implementation_plan_file`. Current mode is {{mode}}.
