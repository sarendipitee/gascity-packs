#!/bin/sh
# workspace-setup.sh - jjw-backed jj workspace creation for Gas City agents.
#
# Usage: workspace-setup.sh <rig-root> <target-dir> <agent-name> [--sync]

set -eu

if [ -n "${TMPDIR:-}" ]; then
    if [ ! -d "$TMPDIR" ] || [ ! -w "$TMPDIR" ]; then
        unset TMPDIR
    fi
fi

RIG_ROOT="${1:?usage: workspace-setup.sh <rig-root> <target-dir> <agent-name> [--sync]}"
REQUESTED_WT="${2:?missing target-dir}"
AGENT="${3:?missing agent-name}"
shift 3

SYNC=""
WORK_BEAD_ID=""
WORK_TITLE=""
WORK_DESCRIPTION_FILE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --sync)
            SYNC="--sync"
            shift
            ;;
        --bead)
            WORK_BEAD_ID="${2:-}"
            shift 2
            ;;
        --title)
            WORK_TITLE="${2:-}"
            shift 2
            ;;
        --description)
            WORK_DESCRIPTION_FILE=$(mktemp)
            printf '%s\n' "${2:-}" > "$WORK_DESCRIPTION_FILE"
            shift 2
            ;;
        --description-file)
            WORK_DESCRIPTION_FILE="${2:-}"
            shift 2
            ;;
        --bead=*)
            WORK_BEAD_ID="${1#--bead=}"
            shift
            ;;
        --title=*)
            WORK_TITLE="${1#--title=}"
            shift
            ;;
        --description=*)
            WORK_DESCRIPTION_FILE=$(mktemp)
            printf '%s\n' "${1#--description=}" > "$WORK_DESCRIPTION_FILE"
            shift
            ;;
        --description-file=*)
            WORK_DESCRIPTION_FILE="${1#--description-file=}"
            shift
            ;;
        *)
            echo "jjw workspace-setup: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

RIG_ROOT=$(python3 - "$RIG_ROOT" <<'PY'
import os
import sys

print(os.path.abspath(sys.argv[1]))
PY
)
REQUESTED_WT=$(python3 - "$RIG_ROOT" "$REQUESTED_WT" <<'PY'
import os
import sys

root, path = sys.argv[1:3]
if os.path.isabs(path):
    print(os.path.normpath(path))
else:
    print(os.path.normpath(os.path.join(root, path)))
PY
)

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# pre_start may launch with cwd already set to WT. First-time setup may stage
# and remove WT, so move to a stable directory before any jj/jjw command.
cd "$RIG_ROOT"

log_step() {
    printf 'jjw workspace-setup: %s\n' "$*" >&2
}

run_best_effort() {
    step="${1:?missing step}"
    shift
    set +e
    "$@"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        log_step "$step failed (exit $rc)"
    fi
    return 0
}

acquire_setup_lock() {
    if ! command -v flock >/dev/null 2>&1; then
        echo "jjw workspace-setup: flock is required to serialize .jjw.yaml updates" >&2
        exit 1
    fi
    lock_dir="$RIG_ROOT/.jj/repo"
    if [ ! -d "$lock_dir" ]; then
        lock_dir="$RIG_ROOT/.jj"
    fi
    mkdir -p "$lock_dir"
    lock_file="$lock_dir/gascity-workspace-setup.lock"
    lock_wait="${GC_JJW_SETUP_LOCK_WAIT_SECONDS:-120}"
    exec 9>"$lock_file"
    if ! flock -w "$lock_wait" 9; then
        echo "jjw workspace-setup: timed out after ${lock_wait}s waiting for $lock_file" >&2
        exit 1
    fi
}

ensure_jjw() {
    if command -v jjw >/dev/null 2>&1; then
        return 0
    fi
    "$SCRIPT_DIR/install-jjw.sh"
    if command -v jjw >/dev/null 2>&1; then
        return 0
    fi
    install_dir="${GC_JJW_INSTALL_DIR:-${HOME:-}/.local/bin}"
    if [ -x "$install_dir/jjw" ]; then
        PATH="$install_dir:$PATH"
        export PATH
        return 0
    fi
    echo "jjw workspace-setup: jjw install completed but jjw is not executable" >&2
    exit 1
}

relpath() {
    python3 - "$1" "$2" <<'PY'
import os, sys
print(os.path.relpath(os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])))
PY
}

abspath_from_root() {
    python3 - "$RIG_ROOT" "$1" <<'PY'
import os, sys
root, path = sys.argv[1], sys.argv[2]
if os.path.isabs(path):
    print(os.path.normpath(path))
else:
    print(os.path.normpath(os.path.join(root, path)))
PY
}

read_config_workspace_dir() {
    config_path="$1"
    if [ ! -f "$config_path" ]; then
        return 1
    fi
    awk -F: '
        /^[[:space:]]*workspace_dir[[:space:]]*:/ {
            value = $2
            sub(/^[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            sub(/^"/, "", value)
            sub(/"$/, "", value)
            print value
            exit
        }
    ' "$config_path"
}

registered_workspace_root() {
    name="$1"
    jj -R "$RIG_ROOT" workspace list -T 'name ++ "\t" ++ root ++ "\n"' 2>/dev/null |
        awk -F '\t' -v want="$name" '$1 == want { print $2; exit }'
}

workspace_root_lookup_failed() {
    case "$1" in
        "<Error:"*) return 0 ;;
        *) return 1 ;;
    esac
}

workspace_name_component() {
    printf '%s' "$1" | sed 's/[^A-Za-z0-9._-]/-/g; s/^-*//; s/-*$//'
}

resolve_base_revset() {
    if [ -n "${GC_JJW_BASE_REVSET:-}" ]; then
        if jj -R "$RIG_ROOT" log -r "$GC_JJW_BASE_REVSET" --no-graph -T '' >/dev/null 2>&1; then
            printf '%s\n' "$GC_JJW_BASE_REVSET"
            return 0
        fi
        echo "jjw workspace-setup: GC_JJW_BASE_REVSET does not resolve: $GC_JJW_BASE_REVSET" >&2
        exit 1
    fi
    if jj -R "$RIG_ROOT" log -r 'default@' --no-graph -T '' >/dev/null 2>&1; then
        printf '%s\n' 'default@'
        return 0
    fi
    for candidate in main master trunk; do
        if jj -R "$RIG_ROOT" log -r "$candidate@origin" --no-graph -T '' >/dev/null 2>&1; then
            printf '%s\n' "$candidate@origin"
            return 0
        fi
    done
    printf '%s\n' '@'
}

write_workspace_runtime_files() {
    mkdir -p "$WT/.beads"
    echo "$RIG_ROOT/.beads" > "$WT/.beads/redirect"

    if [ ! -f "$WT/.jjignore" ]; then
        cat > "$WT/.jjignore" <<'JJIGNORE'
.beads/redirect
.beads/hooks/
.beads/formulas/
.logs/
.claude/
.codex/
.gemini/
.opencode/
.github/hooks/
.github/copilot-instructions.md
__pycache__/
state.json
JJIGNORE
    fi
}

write_work_seed_description() {
    desc_file="$1"
    title="$WORK_TITLE"
    if [ -z "$title" ]; then
        title="$WORK_BEAD_ID"
    fi

    {
        if [ -n "$WORK_BEAD_ID" ]; then
            printf 'work: %s %s\n' "$WORK_BEAD_ID" "$title"
        elif [ -n "$title" ]; then
            printf 'work: %s\n' "$title"
        else
            return 1
        fi
        if [ -n "$WORK_DESCRIPTION_FILE" ] && [ -s "$WORK_DESCRIPTION_FILE" ]; then
            printf '\n'
            sed '/^[[:space:]]*$/d' "$WORK_DESCRIPTION_FILE"
            printf '\n'
        fi
    } > "$desc_file"
}

seed_current_change_from_work_metadata() {
    if [ -z "$WORK_BEAD_ID" ] && [ -z "$WORK_TITLE" ]; then
        return 0
    fi
    if ! jj -R "$WT" root >/dev/null 2>&1; then
        return 0
    fi

    current_change=$(jj -R "$WT" log -r @ --no-graph --template 'change_id' 2>/dev/null || true)
    if [ -z "$current_change" ]; then
        return 0
    fi
    if ! jj -R "$WT" log -r 'no_description' --no-graph --template 'change_id ++ "\n"' 2>/dev/null | grep -q "$current_change"; then
        return 0
    fi

    desc_file=$(mktemp)
    if write_work_seed_description "$desc_file"; then
        jj -R "$WT" describe --stdin < "$desc_file"
    fi
    rm -f "$desc_file"
}

install_workspace_excludes() {
    if ! jj -R "$WT" root >/dev/null 2>&1; then
        return 0
    fi
    git_dir=$(jj -R "$WT" git root 2>/dev/null || true)
    if [ -z "$git_dir" ] || [ ! -d "$git_dir" ]; then
        return 0
    fi
    exclude_file="$git_dir/info/exclude"
    mkdir -p "$(dirname "$exclude_file")"
    touch "$exclude_file"
    if grep -q "# Gas City workspace infrastructure" "$exclude_file" 2>/dev/null; then
        return 0
    fi
    cat >> "$exclude_file" <<'EXCLUDE'

# Gas City workspace infrastructure
.beads/redirect
.beads/hooks/
.beads/formulas/
.logs/
.claude/
.codex/
.gemini/
.opencode/
.github/hooks/
.github/copilot-instructions.md
__pycache__/
state.json
EXCLUDE
}

restore_stage() {
    if [ -n "${STAGE:-}" ] && [ -d "$STAGE" ]; then
        mkdir -p "$WT"
        find "$STAGE" -mindepth 1 -maxdepth 1 | while read -r f; do
            mv "$f" "$WT/" 2>/dev/null || true
        done
        rmdir "$STAGE" 2>/dev/null || true
    fi
}

prepare_jjw_config() {
    config_path="$RIG_ROOT/.jjw.yaml"
    configured_workspace_dir=$(read_config_workspace_dir "$config_path" || true)
    requested_workspace_dir=$(relpath "$(dirname "$REQUESTED_WT")" "$RIG_ROOT")
    workspace_dir="${GC_JJW_WORKSPACE_DIR:-}"
    if [ -z "$workspace_dir" ]; then
        workspace_dir="$requested_workspace_dir"
        if [ -f "$config_path" ] && ! grep -q "Generated by Gas City jjw pack" "$config_path"; then
            workspace_dir="$configured_workspace_dir"
        fi
    fi
    default_branch="${GC_JJW_DEFAULT_BRANCH:-main}"
    bookmark_pattern="${GC_JJW_BOOKMARK_PATTERN:-}"
    if [ -z "$bookmark_pattern" ]; then
        bookmark_pattern='gc/{name}'
    fi
    manage="${GC_JJW_MANAGE_CONFIG:-true}"

    if [ "$manage" = "false" ]; then
        if [ ! -f "$config_path" ]; then
            echo "jjw workspace-setup: $config_path missing and GC_JJW_MANAGE_CONFIG=false" >&2
            exit 1
        fi
        return 0
    fi

    if [ -f "$config_path" ] && ! grep -q "Generated by Gas City jjw pack" "$config_path"; then
        if [ "$manage" != "overwrite" ]; then
            echo "jjw workspace-setup: $config_path exists and is not Gas City-managed" >&2
            echo "jjw workspace-setup: set GC_JJW_MANAGE_CONFIG=overwrite to replace it" >&2
            exit 1
        fi
    fi

    cat > "$config_path" <<EOF
# Generated by Gas City jjw pack. Safe to edit, but set
# GC_JJW_MANAGE_CONFIG=false if this file should not be rewritten by pre_start.
version: 1
workspace_dir: "$workspace_dir"
bookmark_pattern: "$bookmark_pattern"
default_branch: "$default_branch"
EOF
}

refresh_existing_workspace() {
    write_workspace_runtime_files
    install_workspace_excludes
    run_best_effort "update stale workspace state" jj -R "$WT" workspace update-stale >/dev/null 2>&1
    seed_current_change_from_work_metadata
    ensure_workspace_bookmark
    if [ "$SYNC" = "--sync" ]; then
        run_best_effort "sync workspace git state" jj -R "$WT" git fetch 2>/dev/null
    fi
}

ensure_workspace_bookmark() {
    if ! jj -R "$WT" bookmark set -B "$BOOKMARK" -r @ >/dev/null; then
        echo "jjw workspace-setup: failed to set bookmark $BOOKMARK for workspace $WORKSPACE_NAME" >&2
        exit 1
    fi
}

ensure_jjw
acquire_setup_lock
REVSET=$(resolve_base_revset)
WORKSPACE_NAME=$(workspace_name_component "$(basename "$REQUESTED_WT")")
prepare_jjw_config

CONFIGURED_WORKSPACE_DIR=$(read_config_workspace_dir "$RIG_ROOT/.jjw.yaml")
WT=$(abspath_from_root "$CONFIGURED_WORKSPACE_DIR/$WORKSPACE_NAME")
REQUESTED_WT_ABS=$(abspath_from_root "$REQUESTED_WT")
BOOKMARK=$(printf '%s\n' "$bookmark_pattern" | sed "s/{name}/$WORKSPACE_NAME/g")
REGISTERED_WT=$(registered_workspace_root "$WORKSPACE_NAME")
if [ "$REQUESTED_WT_ABS" != "$WT" ]; then
    echo "jjw workspace-setup: refusing to create workspace outside jjw config" >&2
    echo "jjw workspace-setup: requested target: $REQUESTED_WT_ABS" >&2
    echo "jjw workspace-setup: .jjw.yaml target: $WT" >&2
    echo "jjw workspace-setup: update agent work_dir or GC_JJW_WORKSPACE_DIR so they match" >&2
    exit 1
fi

if workspace_root_lookup_failed "$REGISTERED_WT"; then
    if [ -d "$WT/.jj" ] && jj -R "$WT" root >/dev/null 2>&1; then
        log_step "workspace $WORKSPACE_NAME has stale recorded root; refreshing existing target $WT"
        REGISTERED_WT="$WT"
    else
        echo "jjw workspace-setup: workspace name is registered but jj cannot resolve its root" >&2
        echo "jjw workspace-setup: workspace: $WORKSPACE_NAME" >&2
        echo "jjw workspace-setup: requested target: $WT" >&2
        echo "jjw workspace-setup: registered target: $REGISTERED_WT" >&2
        echo "jjw workspace-setup: run from a valid workspace path or forget the stale jj workspace before reusing this name" >&2
        exit 1
    fi
fi

if [ -n "$REGISTERED_WT" ] && [ "$REGISTERED_WT" != "$WT" ]; then
    echo "jjw workspace-setup: workspace name already registered at a different root" >&2
    echo "jjw workspace-setup: workspace: $WORKSPACE_NAME" >&2
    echo "jjw workspace-setup: requested target: $WT" >&2
    echo "jjw workspace-setup: registered target: $REGISTERED_WT" >&2
    echo "jjw workspace-setup: forget or rename the existing jj workspace before reusing this name" >&2
    exit 1
fi

if [ -e "$WT/.jj" ]; then
    refresh_existing_workspace
    exit 0
fi

mkdir -p "$(dirname "$WT")"

STAGE=""
if [ -d "$WT" ] && [ "$(find "$WT" -mindepth 1 -maxdepth 1 | head -n 1)" ]; then
    STAGE=$(mktemp -d "$(dirname "$WT")/.gascity-workspace-stage.XXXXXX")
    find "$WT" -mindepth 1 -maxdepth 1 -exec mv {} "$STAGE"/ \;
    trap 'restore_stage' EXIT HUP INT TERM
fi
rmdir "$WT" 2>/dev/null || true

if jj -R "$RIG_ROOT" log -r "$BOOKMARK" --no-graph -T '' >/dev/null 2>&1; then
    if ! jjw create "$WORKSPACE_NAME" --revision "$REVSET" --bookmark "$BOOKMARK" >/dev/null; then
		echo "jjw workspace-setup: failed to create workspace $WORKSPACE_NAME at $WT from $RIG_ROOT (revset $REVSET, bookmark $BOOKMARK)" >&2
        restore_stage
        exit 1
    fi
elif ! jjw create "$WORKSPACE_NAME" --revision "$REVSET" >/dev/null; then
	echo "jjw workspace-setup: failed to create workspace $WORKSPACE_NAME at $WT from $RIG_ROOT (revset $REVSET)" >&2
	restore_stage
	exit 1
fi

if [ ! -d "$WT/.jj" ]; then
    echo "jjw workspace-setup: jjw reported success but $WT/.jj is missing" >&2
    restore_stage
    exit 1
fi

restore_stage
trap - EXIT HUP INT TERM
write_workspace_runtime_files
install_workspace_excludes
seed_current_change_from_work_metadata
ensure_workspace_bookmark

if [ "$SYNC" = "--sync" ]; then
    run_best_effort "sync workspace git state" jj -R "$WT" git fetch 2>/dev/null
fi
