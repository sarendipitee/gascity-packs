{{ define "jj-basics" }}
# JJ Basics for Pack Work

This fragment gives packsmith agents the minimal Jujutsu commands they need to
land in a workspace, claim a bead, keep their work visible and isolated, and
finish cleanly.

## Workspace references and bookmarks

In this repo:

- `default@` is the working copy of the rig-root **default workspace**. Pack
  work reaches it only after the pack-named integration workspace has absorbed
  the pack's child workspaces and is ready for running Gas City.
- `.gc/workspaces/<rig>/packs/<pack>` is the pack-named **integration
  workspace** for that pack. It can receive normal pack work and can also
  integrate work from child workspaces for the same pack.
- `.gc/workspaces/<rig>/packs/<pack>/<workspace>` is an isolated child
  workspace. It starts from the pack integration head when that head exists and
  lands back into the pack-named workspace, not directly to `default@`.
- `main` is the **published integration bookmark** for `gascity-packs`. Landed
  pack work is released to `main` only after testing on `default@`.
- `main@origin` is the live published `main` on the `origin` remote.
- `gc/<pack>` tracks the live `@` of the pack-named integration workspace.
  Child workspace bookmarks use `gc/<pack>.<workspace>`.

Do not confuse `default@` (a workspace reference) with a `default` bookmark. If a
`default` bookmark exists, it is unrelated to `default@` and should be ignored.

## Land in a session and claim a bead

When a packsmith session starts, it is already pointed at the right sparse jj
workspace by the packer pre-start script. Your first action is to claim routed
work and record a clear workspace commit for it.

```bash
# Claim the routed bead assigned to this session
gc hook --claim --json

# Record the workspace position tied to this claim
jj describe -m "<pack>: <short task summary>"
```

Describing the change at the start creates a visible commit linked to the
session, prevents accidental mixing with the previous agent's work, and gives
other workspaces (and the dashboard) a readable signal of who is doing what.

If the claim returns `NO_ROUTED_WORK` or `CONFIG_REJECTED`, drain and exit
instead of inventing work.

## Bookmark hygiene

Pack workspaces use bookmarks in the `gc/<pack>` or `gc/<pack>.<workspace>`
namespace. The integration target depends on the current workspace:

- from the pack-named workspace, integrate onto `default@`
- from a child workspace under a pack, integrate onto `gc/<pack>` by moving the
  pack-named workspace to the landed tip

Only `mol-packer-complete` moves these integration targets. The `main` bookmark
is released by the packrouter release workflow after testing.

- Do not move `default@` unless you are running `mol-packer-complete` from the
  pack-named integration workspace.
- Do not move `main` from a pack workspace.
- Do not create ad-hoc bookmarks; use `jj describe` and `jj new` to manage your
  local line instead.
- Do not run `jj op restore`; the operation log is shared across workspaces and
  you can rewind another session's state.

## Revset and stack management

Useful revsets for day-to-day pack work:

| Goal | Revset |
| --- | --- |
| Commits from the current integration base to your working copy | `<integration-base>..@` |
| Commits in this workspace line | `@ \| @- \| <integration-base>` |
| Changes in your working copy | `jj diff --git` |
| Files changed on your branch | `jj diff --from <integration-base> --to @ --stat` |
| Check for conflicts | `jj log -r 'conflicts()'` |
| Check for divergent bookmarks | `jj log -r 'divergent()'` |
| Child workspace integration base | `gc/<pack>` |
| Pack workspace integration base | `default@` |
| Live published state | `main@origin` |

Use `gc/<pack>` as `<integration-base>` in child workspaces and `default@` as
`<integration-base>` in the pack-named integration workspace. Rebase onto the
current integration base only when the bead or formula says so, when that base
has moved forward, or when you are about to run `mol-packer-complete`. Do not
rebase after every trivial change by default.

## Work finished formula

When the bead task is complete, run `mol-packer-complete` from inside the pack
workspace. It guides you through reviewing, cleaning, rebasing onto the current
integration base when needed, moving the correct integration workspace to the
landed tip, verifying, and leaving a clean working copy.

The current integration base is `gc/<pack>` from a child workspace and
`default@` from the pack-named integration workspace.

Summary of the landing sequence:

```bash
# Review
jj status
jj log -r '<integration-base>..@' --no-graph
jj diff --git
jj diff --from <integration-base> --to @ --stat

# Clean (as needed)
jj squash
jj describe -m "<pack>: <clear summary>"
jj abandon <empty-change-id>

# Rebase onto the current integration base only if needed
jj rebase -s <first-local-change> -d <integration-base>

# From a child workspace, move the pack-named workspace to the landed tip
jj -R <pack-integration-workspace-dir> edit <tip-change-id>

# From the pack-named integration workspace, move default@ to the landed tip
jj -R <rig-root> edit <tip-change-id>

# Verify
gc lint <pack>
python3 -m pytest <relevant-tests> -q

# Leave a clean working copy
jj new <integration-base>
```

After a child workspace lands, the pack-named integration workspace is at the
pack's integrated tip and can keep receiving work for that pack. After the
pack-named workspace lands to `default@`, the rig-root default workspace is
ready for testing in a running Gas City. Release to `main` is handled separately
by the packrouter release workflow.
{{ end }}
