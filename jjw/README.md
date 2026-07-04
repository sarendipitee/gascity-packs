# jjw

Gas City pack for managing Jujutsu agent workspaces with
[`jjw`](https://github.com/aranw/jjw).

The pack provides:

- `assets/scripts/install-jjw.sh`: installs `jjw` with `go install` when it is
  not already on `PATH`.
- `assets/scripts/workspace-setup.sh`: pre-start helper for agent workspaces.
- `assets/scripts/workspace-report.sh`: direct workspace health report helper.
- `gc jjw install`: explicit install command.
- `gc jjw workspace-report`: prints a `jjw`-backed workspace report.
- `formulas/mol-jjw-workspace-report.toml`: dog formula for appending a
  workspace report to the claimed bead.
- `orders/workspace-report.toml`: direct exec smoke report order.
- `orders/jjw-workspace-report.toml`: formula-backed dog report order.
- `doctor/check-jjw`: `gc doctor` check that verifies the binary can be
  installed/resolved.
- `template-fragments/jjw-workspace-setup.template.md`: shared prompt guidance
  for `jjw`-managed Gas City workspaces.
- `template-fragments/jjw-workspace-reporting.template.md`: shared prompt
  guidance for report-producing agents.

## Agent usage

Use from another imported pack:

```toml
[imports.jjw]
source = "../jjw"
```

```toml
pre_start = ["{{.ConfigDir}}/../jjw/assets/scripts/workspace-setup.sh {{.RigRoot}} {{.WorkDir}} {{.AgentBase}} --sync"]
```

## Workspace setup contract

`assets/scripts/workspace-setup.sh` is the public setup entry point for consumer
packs. Its positional arguments are the rig root, the target workspace
directory, and the workspace name. Optional flags are `--sync`, `--bead`,
`--title`, `--description`, and `--description-file`.

The helper resolves `install-jjw.sh` from its own script directory, not from the
agent process working directory. Consumer packs should call it through their
imported `jjw` path and pass Gas City template values (`{{.RigRoot}}`,
`{{.WorkDir}}`, and `{{.AgentBase}}`) directly.

The helper creates/uses a `.jjw.yaml` in the rig root. It writes that file only
when missing or when it already contains the Gas City marker.

The `work_dir` passed by Gas City must resolve to the same path that `jjw`
derives from `.jjw.yaml`'s `workspace_dir` plus the workspace name. The helper
refuses to create a workspace when those paths disagree, because that would
leave one path owned by Gas City process launch and another path owned by
`jjw`.

The helper also accepts LazyJJ metadata flags such as `--bead`, `--title`, and
`--description-file`. When title metadata is present, it describes an
undescribed current workspace change so fresh and resumed workspaces start with
bead-derived context. The formula remains responsible for validating and
recording workspace metadata.

Wrapper packs may set `GC_JJW_WORKSPACE_DIR`, `GC_JJW_BASE_REVSET`, and
`GC_JJW_BOOKMARK_PATTERN` before calling this helper. Any sparse checkout
policy belongs to the wrapper after `workspace-setup.sh` returns.

Known consumers:

- `packer/assets/scripts/pack-workspace-setup.sh` wraps this helper so pack
  workspaces can set pack integration bookmarks and then apply pack sparse
  patterns.
- `jj-hunk/agents/surgeon/agent.toml` calls this helper directly for isolated
  surgeon workspaces and passes optional bead metadata.

## Hook environment

Upstream `jjw` lifecycle hooks expose workspace facts while hooks run:

- `JJW_NAME`: workspace name
- `JJW_PATH`: absolute workspace path
- `JJW_BOOKMARK`: associated bookmark
- `JJW_REPO_ROOT`: repository root containing `.jjw.yaml`
- `JJW_JJ_ROOT`: jj repository root
- `JJW_WORKSPACE_DIR`: configured workspace directory name
- `JJW_INDEX`: allocated workspace index, when available

Packs that integrate with `jjw` should treat these as lifecycle inputs, not as
durable job state. For example, `gastown-lazyjj` prefers `JJW_NAME` and
`JJW_PATH` when its formula records the claimed bead's workspace, then persists
those facts to bead metadata for runner handoff and recovery.

## Template fragments

Import the prompt fragments when another pack needs reusable workspace setup or
reporting guidance:

- `jjw-workspace-setup`: explains the `workspace-setup.sh` pre-start contract,
  the `JJW_*` hook facts, and the path-mismatch safety rule.
- `jjw-workspace-reporting`: documents the command, script, formula, and order
  entry points for producing a `jjw list --verbose` report.

## Configuration

Set these through `city.toml` agent/rig env overrides when needed:

- `GC_JJW_VERSION`: version passed to `go install`; default `latest`.
- `GC_JJW_INSTALL_DIR`: install directory; default `$HOME/.local/bin`.
- `GC_JJW_WORKSPACE_DIR`: `jjw` workspace_dir override. Default is the target
  workspace parent, relative to the rig root.
- `GC_JJW_BASE_REVSET`: base revision for new workspaces. Default resolves to
  `default@`, then a remote main branch, then `@`.
- `GC_JJW_DEFAULT_BRANCH`: `jjw` default_branch; default `main`.
- `GC_JJW_BOOKMARK_PATTERN`: `jjw` bookmark_pattern; default `gc/{name}`.
- `GC_JJW_MANAGE_CONFIG`: `true` by default. Set `overwrite` to replace a
  hand-authored `.jjw.yaml`; set `false` to require an existing config.
