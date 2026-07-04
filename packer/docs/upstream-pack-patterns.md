# Upstream Pack Patterns

Research date: 2026-06-21

This note captures the packrouter research pass over established packs in this
repository. Use it when routing fork-pack alignment work.

## Established Baseline

The mature packs are not identical, but they share a few structural patterns:

- `pack.toml` uses `[pack]`, `schema = 2`, `name`, `version` when versioned,
  and a short description. Cross-pack asset reuse is declared through
  `[imports.<pack>]` rather than by silently reaching across directories.
- Pack entry points are discoverable from README sections. Mature READMEs name
  import/composition, commands, formulas, checks, and runtime expectations.
- Long-running implementation agents use `agent.toml` with explicit `scope`,
  `provider`, `wake_mode`, `formula`, `work_dir`, `nudge`, `pre_start`, and
  session bounds. Workspace agents set up their working directory in
  `pre_start`.
- Workspace setup is script-backed and idempotent. Established examples are
  `gastown/assets/scripts/worktree-setup.sh`,
  `gastown-lazyjj/assets/scripts/workspace-setup.sh`, and
  `jjw/assets/scripts/workspace-setup.sh`.
- Tmux UX is centralized in mature pack scripts rather than recreated per
  agent. Reuse the normal helpers from `gastown/assets/scripts/` and
  `gastown-lazyjj/assets/scripts/tmux-scroll.sh` where the pack exposes tmux
  behavior.
- Formula packs either provide small direct formulas or structured v2 formulas
  with variables, step metadata, `description_file` assets, and check scripts.
  Validation is part of the formula contract, not an afterthought.
- Mature adapter packs have pack-local tests or root tests. Shape/compatibility
  tests should cover pack manifests, commands, agents, formula references,
  scripts, and import assumptions.

## Active Fork Pack Gaps

`packer`:

- Correctly imports `jjw` and wraps `jjw/assets/scripts/workspace-setup.sh`
  through `packer/assets/scripts/pack-workspace-setup.sh`.
- Needs packsmith routing/claim behavior to preserve one resident default
  pack workspace per pack during integration testing.
- Needs explicit packsmith contract text for no-drain main pack workspaces and
  mature tmux/script reuse.

`jj-hunk`:

- Has agents, commands, doctors, formulas, skills, README, and docs.
- Uses `jjw/assets/scripts/workspace-setup.sh` from agent config, so manifest
  imports and tests should prove that dependency is available.
- Has no mature-pack-style local shape test in the scan and no tmux script
  reuse coverage.

`jjw`:

- Provides the shared jj workspace setup scripts and commands.
- Already has a local shape test and README sections for agent usage, hook
  environment, template fragments, and configuration.
- Should be treated as shared infrastructure for dependent packs; changes need
  compatibility tests for consumers such as `jj-hunk` and `packer`.

`megamerge-workflow`:

- Has a focused agent, formula, skill, pack manifest, and README.
- Lacks workspace setup scripts, tests, docs beyond README, and tmux/script
  reuse coverage.
- Should align with the mature single-agent pack shape while declaring any
  upstream script dependencies explicitly.

`gastown-lazyjj`:

- Is the strongest upstream-style reference for jj workspace packs: agents,
  formulas, skills, workspace setup, tmux-scroll, orders, and template
  fragments are present.
- Use it as the local pattern source for jj workspace lifecycle, no ad hoc tmux
  behavior, and tutorial-aligned workflow docs.

## Routing Requirements

When creating alignment beads:

- Route implementation to the target pack's default reusable pack workspace.
- Tell packsmiths that main/default pack workspaces are persistent
  integration/testing lanes. They must not `drain-ack` after validation or
  after an empty follow-up check.
- Tell packsmiths to preserve and reuse mature tmux helpers:
  `gastown/assets/scripts/agent-menu.sh`,
  `gastown/assets/scripts/bind-key.sh`,
  `gastown/assets/scripts/cycle.sh`,
  `gastown/assets/scripts/status-line.sh`,
  `gastown/assets/scripts/tmux-keybindings.sh`,
  `gastown/assets/scripts/tmux-theme.sh`, and
  `gastown-lazyjj/assets/scripts/tmux-scroll.sh`.
- Require `gc lint <pack>` plus pack-local/root shape tests for any structural
  change.
- Prefer explicit imports and tests over implicit relative path coupling.
