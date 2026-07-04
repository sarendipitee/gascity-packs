---
name: lazyjj-workspace
description: Use LazyJJ workspace and stack conventions for Gas Town jj jedi work.
category: development
allowed-tools: Bash
---

# LazyJJ Workspace Workflow

Use this skill when a Gas Town jj jedi is assigned work through
`mol-polecat-lazyjj-work`.

For the tutorial-oriented overview, also see [`README.md`](../../README.md).
The pack now ships reusable template fragments for the mental model, stack
workflow, PR workflow, and LazyJJ config reference.

## Requirements

The session launcher must already place the jedi in its assigned jj
workspace. This skill does not create workspaces.

The host jj config must provide the LazyJJ revset aliases:

```bash
jj log -r branch_off
jj log -r stack_base
jj log -r stack
jj log -r no_description
```

The preferred checkpoint command is:

```bash
jj claude-checkpoint "short description"
```

If that alias is unavailable, use:

```bash
jj new -m "next"
jj describe -r @- -m "short description"
```

## Model

- The jedi's current jj workspace owns the work.
- The workspace's `@` is the jedi working head.
- A stack is inferred from jj graph ancestry, not from a separate database.
- Bead metadata only links the work bead to the workspace, stack revset, and
  review bookmark.
- Bookmarks are review/export handles. Do not create a bookmark before useful
  work exists.
- The canonical sync path uses existing jj tools: `jj edit <stack-head>` to
  move a workspace onto the integrated head, and `jj absorb` / `jj rebase`
  when useful local changes need to stay on the stack instead of being copied.
  The two live workspaces should converge on the same head through history
  operations, not file copying.

## Required Bead Metadata

Record these on the work bead as soon as the formula starts:

```text
lazyjj_workspace
lazyjj_workspace_dir
```

Record these at submit time:

```text
lazyjj_review_bookmark
lazyjj_stack_revset
```

## Workspace Names

LazyJJ workspaces are persistent agent workspaces, not one-off bead workspaces.
The workspace setup script uses a stable `rig/role/label` name such as
`gascity-packs/jedi/furiosa` or `gascity-packs/tasksmith/default`.
Pool agents must get unique stable labels up front; setup fails on duplicate
workspace names instead of appending numeric or hash suffixes.

Bead ids are still passed to setup when available, but only as job context for
the initial change description and bead metadata. Do not name a persistent jj
workspace after a transient bead id.

## Stack Commands

Use these for normal inspection:

```bash
jj status
jj log -r 'trunk() | branch_off | stack'
jj log -r 'stack & no_description'
jj diff --from branch_off
jj log -r 'trunk()..@'
```

If a fix belongs in an earlier stack commit, prefer:

```bash
jj absorb
```

If exact hunk movement is required, use `jj-hunk` rather than an interactive
jj split/squash UI.

## PR Workflow

For independent PRs that can land in any order:

```bash
jj spr init
jj spr diff --cherry-pick
jj spr list
jj spr land --cherry-pick -r <change-id>
```

For a dependent LazyJJ stack, use the workspace handoff path:

```bash
jj bookmark set <bookmark> -r @-
jj git push --bookmark <bookmark>
```

## Publish Policy

This pack is allowed to publish the formula's review bookmark when the formula
sets `publish_mode = "push"`. That is a formula-specific exception to generic
jj-vcs no-push guidance.

If `publish_mode = "handoff"`, do not push. Set the review bookmark locally and
record metadata on the bead for runner/default workspace integration.
