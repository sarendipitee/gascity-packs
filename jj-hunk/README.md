# jj-hunk Pack

Agent-safe hunk selection workflows for Jujutsu repositories.

This pack wraps `jj-hunk-tool` and installs two skills from
`mvzink/jj-hunk-tool`:

- `jj-subagent-workspaces` for shaping isolated jj workspace tasks.
- `jj-surgeon` for implementing hunk-level jj changes safely.

## Import and Composition

`pack.toml` imports `jjw` because the surgeon agent uses the shared
`jjw/assets/scripts/workspace-setup.sh` lifecycle helper from its `pre_start`
hook. Keep that dependency explicit in the manifest whenever the agent
workspace setup contract changes.

The pack does not ship local tmux or workspace lifecycle scripts. If a jj-hunk
entrypoint needs tmux behavior, reuse the mature helpers from
`gastown/assets/scripts/agent-menu.sh`,
`gastown/assets/scripts/bind-key.sh`, `gastown/assets/scripts/cycle.sh`,
`gastown/assets/scripts/status-line.sh`,
`gastown/assets/scripts/tmux-keybindings.sh`,
`gastown/assets/scripts/tmux-theme.sh`, or
`gastown-lazyjj/assets/scripts/tmux-scroll.sh` instead of adding ad hoc session
handling here.

## Sessions

- `tasksmith`: creates claim-sized hunk-surgery beads that follow the
  subagent workspace workflow.
- `surgeon`: implements those beads in a LazyJJ-style jj workspace.

## Commands

- `gc jj-hunk list`
- `gc jj-hunk spec`
- `gc jj-hunk split`
- `gc jj-hunk commit`
- `gc jj-hunk squash`
- `gc jj-hunk lightjj-annotate`

The hunk-editing wrappers are intentionally thin and delegate to `jj-hunk`.

`gc jj-hunk lightjj-annotate` bridges `jj-hunk-tool absorb --dry-run --debug`
into lightjj review annotations. It previews by default and only posts when
`--post` is passed.

## Formulas

- `mol-jj-hunk-work`: implement one hunk-level task.
- `mol-jj-hunk-subagent-task`: shape hunk-level work for isolated subagents.

## Docs

- `docs/diagrams/mol-jj-hunk-work.md`
- `docs/diagrams/mol-jj-hunk-subagent-task.md`
- `docs/diagrams/README.md`

## Checks

Run:

```bash
gc lint jj-hunk
python3 -m pytest tests/test_jj_hunk_pack_shape.py -q
gc doctor --json
gc formula show mol-jj-hunk-work
gc formula show mol-jj-hunk-subagent-task
gc prime gascity-packs/jj-hunk.tasksmith --strict
gc prime surgeon --strict
```
