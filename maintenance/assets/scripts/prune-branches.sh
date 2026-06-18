#!/usr/bin/env bash
# prune-branches — clean stale gc/* and polecat/* worktree branches from all rigs.
#
# These branches are created by coding agents for worktree isolation.
# After work is merged and the remote branch deleted, local tracking
# branches persist indefinitely. This script prunes them.
#
# Runs as an exec order (no LLM, no agent, no wisp).
set -euo pipefail

CITY="${GC_CITY:-.}"
PRUNED=0
DEFAULT_BRANCH="${GC_DEFAULT_BRANCH:-live}"
TMP_BEADS="$(mktemp)"
trap 'rm -f "$TMP_BEADS"' EXIT

# Get all rig paths.
RIGS=$(gc rig list --json 2>/dev/null | jq -r '.rigs[].path' 2>/dev/null) || exit 0
if [ -z "$RIGS" ]; then
    exit 0
fi

# Snapshot bead metadata once so branch pruning can make a conservative
# decision without repeated full-database scans per ref.
if ! gc bd list --json --limit=0 2>/dev/null >"$TMP_BEADS"; then
    exit 0
fi

bead_for_branch() {
    local branch="$1"
    jq -r --arg branch "$branch" '
        .[]
        | select((.metadata.branch // "") == $branch)
        | @base64
    ' "$TMP_BEADS" 2>/dev/null | head -n1
}

branch_is_safe_to_prune() {
    local rig_path="$1"
    local branch="$2"
    local bead_payload="$3"
    local bead_json
    local status
    local rejection_reason
    local target

    [ -n "$bead_payload" ] || return 1
    bead_json=$(printf '%s' "$bead_payload" | base64 --decode 2>/dev/null) || return 1
    status=$(printf '%s' "$bead_json" | jq -r 'if type == "array" then .[0].status else .status end // empty' 2>/dev/null)
    rejection_reason=$(printf '%s' "$bead_json" | jq -r 'if type == "array" then .[0].metadata.rejection_reason else .metadata.rejection_reason end // empty' 2>/dev/null)
    target=$(printf '%s' "$bead_json" | jq -r 'if type == "array" then .[0].metadata.target else .metadata.target end // empty' 2>/dev/null)

    # Only prune branches for closed beads. Rejected or still-open work
    # remains evidence and must stay on disk.
    [ "$status" = "closed" ] || return 1
    [ -z "$rejection_reason" ] || return 1

    # `gc/*` refs are only pruned once their remote ref is gone; polecat refs
    # may be pruned locally once the bead is closed and the commit is already
    # represented on the recorded target.
    if [ "${branch#polecat/}" = "$branch" ]; then
        if git -C "$rig_path" show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
            return 1
        fi
    fi

    # Use the recorded target if present, otherwise fall back to the default
    # branch. Patch-equivalent landings are safe to prune when the branch's tip
    # is already represented on the target history.
    if [ -z "$target" ]; then
        target="$DEFAULT_BRANCH"
    fi
    if git -C "$rig_path" show-ref --verify --quiet "refs/remotes/origin/$target" 2>/dev/null; then
        if git -C "$rig_path" merge-base --is-ancestor "$branch" "origin/$target" 2>/dev/null; then
            return 0
        fi
        if ! git -C "$rig_path" cherry "origin/$target" "$branch" 2>/dev/null | grep -q '^+'; then
            return 0
        fi
    fi

    return 1
}

while IFS= read -r rig_path; do
    [ -d "$rig_path/.git" ] || continue

    # Fetch and prune remote refs.
    git -C "$rig_path" fetch --prune origin 2>/dev/null || continue

    # List gc/* and polecat/* branches.
    BRANCHES=$(
        {
            git -C "$rig_path" branch --list 'gc/*' --format='%(refname:short)'
            git -C "$rig_path" branch --list 'polecat/*' --format='%(refname:short)'
        } 2>/dev/null | sort -u
    ) || continue
    if [ -z "$BRANCHES" ]; then
        continue
    fi

    CURRENT=$(git -C "$rig_path" branch --show-current 2>/dev/null) || true

    while IFS= read -r branch; do
        # Skip current branch.
        [ "$branch" = "$CURRENT" ] && continue

        BEAD=$(bead_for_branch "$branch")
        if branch_is_safe_to_prune "$rig_path" "$branch" "$BEAD"; then
            git -C "$rig_path" branch -D "$branch" 2>/dev/null && PRUNED=$((PRUNED + 1))
        fi
    done <<< "$BRANCHES"
done <<< "$RIGS"

if [ "$PRUNED" -gt 0 ]; then
    echo "prune-branches: deleted $PRUNED stale branches"
fi
