#!/bin/sh
# workspace-setup.sh — idempotent jj workspace creation for Gas City agents.
#
# Usage: workspace-setup.sh <rig-root> <target-dir> <agent-name> [--sync] [--bead <id>] [--title <title>] [--description <text>|--description-file <path>]
#
# Creates a jj workspace at <target-dir> linked to the rig repo at <rig-root>.
# Workspaces share the rig's commit graph so agents work in isolated sandboxes
# that can rebase into each other's lineages without merge commits.
#
# Base revision: resolves to the rig's default workspace (`default@`) so new
# agent workspaces branch from the local integration head. Falls back to the
# default remote bookmark only when the repo has no default workspace.
#
# Called from pre_start in pack configs. Runs before the session is created
# so the agent starts IN the workspace directory.

set -eu

RIG_ROOT="${1:?usage: workspace-setup.sh <rig-root> <target-dir> <agent-name> [--sync] [--bead <id>] [--title <title>] [--description <text>|--description-file <path>]}"
WT="${2:?missing target-dir}"
AGENT="${3:?missing agent-name}"
shift 3

SYNC=""
WORK_BEAD_ID="${LAZYJJ_WORK_BEAD_ID:-}"
WORK_TITLE="${LAZYJJ_WORK_TITLE:-}"
WORK_DESCRIPTION="${LAZYJJ_WORK_DESCRIPTION:-}"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --sync)
            SYNC="--sync"
            shift
            ;;
        --bead)
            WORK_BEAD_ID="${2:?--bead requires an id}"
            shift 2
            ;;
        --bead=*)
            WORK_BEAD_ID="${1#--bead=}"
            shift
            ;;
        --title)
            WORK_TITLE="${2:?--title requires text}"
            shift 2
            ;;
        --title=*)
            WORK_TITLE="${1#--title=}"
            shift
            ;;
        --description)
            WORK_DESCRIPTION="${2:?--description requires text}"
            shift 2
            ;;
        --description=*)
            WORK_DESCRIPTION="${1#--description=}"
            shift
            ;;
        --description-file)
            WORK_DESCRIPTION="$(cat "${2:?--description-file requires a path}")"
            shift 2
            ;;
        --description-file=*)
            WORK_DESCRIPTION="$(cat "${1#--description-file=}")"
            shift
            ;;
        *)
            echo "workspace-setup: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

explicit_bead_id() {
    if [ -n "$WORK_BEAD_ID" ]; then
        printf '%s\n' "$WORK_BEAD_ID"
        return 0
    fi
    return 1
}

write_bead_change_description() {
    bead_id="${1:-}"
    out="${2:?missing output path}"

    if [ -n "$WORK_TITLE" ]; then
        title=$(printf '%s' "$WORK_TITLE" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')
        body=$(printf '%s' "$WORK_DESCRIPTION" | sed '/^[[:space:]]*$/d')
        {
            printf 'work: %s\n' "$title"
            if [ -n "$body" ]; then
                printf '\n%s\n' "$body"
            fi
        } > "$out"
        return 0
    fi

    if [ -z "$bead_id" ] || ! command -v bd >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        return 1
    fi

    bead_json=$(bd show "$bead_id" --json 2>/dev/null || true)
    if [ -z "$bead_json" ]; then
        return 1
    fi

    title=$(printf '%s' "$bead_json" | jq -r '.[0].title // .title // empty' 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')
    body=$(printf '%s' "$bead_json" | jq -r '.[0].description // .[0].notes // .description // .notes // empty' 2>/dev/null | sed '/^[[:space:]]*$/d')
    if [ -z "$title" ]; then
        title="$bead_id"
    fi

    {
        printf 'work: %s %s\n' "$bead_id" "$title"
        if [ -n "$body" ]; then
            printf '\n%s\n' "$body"
        fi
    } > "$out"
}

describe_workspace_change_from_bead() {
    if ! bead_id=$(explicit_bead_id); then
        return 0
    fi

    is_empty=$(jj -R "$WT" log -r @ --no-graph --template 'if(empty, "1", "0")' 2>/dev/null || printf '0')
    current_desc=$(jj -R "$WT" log -r @ --no-graph --template 'description.first_line()' 2>/dev/null || true)
    if [ "$is_empty" != "1" ] && [ -n "$current_desc" ]; then
        return 0
    fi

    desc_file=$(mktemp)
    if write_bead_change_description "$bead_id" "$desc_file"; then
        jj -R "$WT" describe --stdin < "$desc_file" >/dev/null 2>&1 || true
    fi
    rm -f "$desc_file"
}

write_workspace_runtime_files() {
    # Bead redirect: point .beads at the rig's bead store so bd commands work
    # from inside the workspace without a separate bead database.
    mkdir -p "$WT/.beads"
    echo "$RIG_ROOT/.beads" > "$WT/.beads/redirect"

    # Write .jjignore as a visible hint only when the repo does not already
    # have one. jj currently uses git excludes installed below.
    if [ ! -e "$WT/.jjignore" ]; then
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
skill-catalog-*.b64
__pycache__/
state.json
JJIGNORE
    fi
}

runtime_ignore_patterns() {
    cat <<'IGNORE'
# Gas City workspace runtime
/.jjignore
/.beads/redirect
/.beads/hooks/
/.beads/formulas/
/.gc/
/.logs/
/.claude/
/.codex/
/.gemini/
/.opencode/
/.github/hooks/
/.github/copilot-instructions.md
/skill-catalog-*.b64
/tmp/
__pycache__/
/settings.json
/state.json
IGNORE
}

install_workspace_excludes() {
    git_dir=$(jj -R "$WT" git root 2>/dev/null || true)
    if [ -z "$git_dir" ]; then
        return 0
    fi

    exclude="$git_dir/info/exclude"
    mkdir -p "$(dirname "$exclude")"
    touch "$exclude"
    if grep -q '^/skill-catalog-\*.b64$' "$exclude"; then
        return 0
    fi

    {
        printf '\n# BEGIN Gas City LazyJJ workspace runtime\n'
        runtime_ignore_patterns
        printf '# END Gas City LazyJJ workspace runtime\n'
    } >> "$exclude"
}

workspace_name_component() {
    printf '%s' "$1" |
        tr '[:upper:]' '[:lower:]' |
        sed 's/[^a-z0-9._-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//'
}

workspace_role_from_path() {
    role=$(basename "$(dirname "$WT")")
    workspace_name_component "$role"
}

workspace_label_from_subject() {
    role="${1:?missing role}"
    subject=$(basename "$WT")
    case "$subject" in
        *.*)
            label="${subject##*.}"
            ;;
        *)
            label="$subject"
            ;;
    esac
    label=$(workspace_name_component "$label")
    if [ -z "$label" ] || [ "$label" = "$role" ]; then
        label="default"
    fi
    printf '%s\n' "$label"
}

workspace_name_exists_elsewhere() {
    name="${1:?missing workspace name}"
    jj -R "$RIG_ROOT" workspace list -T 'name ++ " " ++ root ++ "\n"' 2>/dev/null |
        awk -v name="$name" -v wt="$WT" '$1 == name && $2 != wt { found = 1 } END { exit(found ? 0 : 1) }'
}

derive_workspace_name() {
    rig=$(workspace_name_component "$(basename "$RIG_ROOT")")
    role=$(workspace_role_from_path)
    if [ -n "$rig" ] && [ -n "$role" ]; then
        label=$(workspace_label_from_subject "$role")
        candidate="$rig-$role-$label"
    else
        candidate=$(workspace_name_component "$AGENT")
    fi

    printf '%s\n' "$candidate"
}

restore_stage() {
    if [ -n "${STAGE:-}" ] && [ -d "$STAGE" ]; then
        find "$STAGE" -mindepth 1 -maxdepth 1 | while read -r f; do
            mv "$f" "$WT/" 2>/dev/null || true
        done
        rm -rf "$STAGE"
    fi
}

resolve_base_revset() {
    # Fetch latest from remotes before resolving remote fallback revsets.
    jj -R "$RIG_ROOT" git fetch 2>/dev/null || true

    # Prefer default@, which LazyJJ uses as the local integration target.
    # Fall back through common remote bookmark names, then the rig's current @.
    if jj -R "$RIG_ROOT" log -r 'default@' --no-graph -T '' >/dev/null 2>&1; then
        printf '%s\n' "default@"
        return 0
    fi
    if jj -R "$RIG_ROOT" log -r 'trunk()@origin' --no-graph -T '' >/dev/null 2>&1; then
        printf '%s\n' "trunk()@origin"
        return 0
    fi
    for candidate in main master trunk; do
        if jj -R "$RIG_ROOT" log -r "$candidate@origin" --no-graph -T '' >/dev/null 2>&1; then
            printf '%s\n' "$candidate@origin"
            return 0
        fi
    done
    printf '%s\n' "@"
}

workspace_stack_nonempty() {
    base="${1:?missing base revset}"
    [ -n "$(jj -R "$WT" log -r "$base..@ & ~empty()" --no-graph -T 'change_id.short() ++ "\n"' 2>/dev/null || true)" ]
}

workspace_is_empty_child_of_base() {
    base="${1:?missing base revset}"
    is_empty=$(jj -R "$WT" log -r @ --no-graph -T 'if(empty, "1", "0")' 2>/dev/null || printf '0')
    if [ "$is_empty" != "1" ]; then
        return 1
    fi
    jj -R "$WT" log -r "@- & $base" --no-graph -T '' >/dev/null 2>&1
}

refresh_existing_workspace() {
    base="${1:?missing base revset}"

    write_workspace_runtime_files
    install_workspace_excludes
    jj -R "$WT" workspace update-stale >/dev/null 2>&1 || true

    if [ "$SYNC" = "--sync" ]; then
        jj -R "$WT" git fetch 2>/dev/null || true
    fi

    if workspace_stack_nonempty "$base"; then
        stack_roots="roots($base..@ & ~empty() & mutable())"
        if ! jj -R "$WT" rebase -s "$stack_roots" -d "$base" >/dev/null; then
            echo "workspace-setup: failed to rebase existing workspace stack onto $base" >&2
            echo "workspace-setup: create a temporary megamerge with: jj new $base @ -m \"megamerge: inspect workspace refresh\"" >&2
            exit 1
        fi
    elif workspace_is_empty_child_of_base "$base"; then
        :
    else
        jj -R "$WT" new "$base" -m "workspace: refresh from $base" >/dev/null
    fi

    describe_workspace_change_from_bead
}

REVSET=$(resolve_base_revset)

# Idempotent refresh: existing workspaces must not keep looking at a stale head.
if [ -d "$WT/.jj" ]; then
    refresh_existing_workspace "$REVSET"
    exit 0
fi

mkdir -p "$(dirname "$WT")"

# Stage any pre-existing content in the target directory so it isn't lost
# when jj checks out the workspace revision.
STAGE=""
if [ -d "$WT" ] && [ "$(find "$WT" -mindepth 1 -maxdepth 1 | head -n 1)" ]; then
    STAGE=$(mktemp -d "$(dirname "$WT")/.gascity-workspace-stage.XXXXXX")
    find "$WT" -mindepth 1 -maxdepth 1 -exec mv {} "$STAGE"/ \;
    trap 'restore_stage' EXIT HUP INT TERM
fi
rmdir "$WT" 2>/dev/null || true

WORKSPACE_NAME=$(derive_workspace_name)
if workspace_name_exists_elsewhere "$WORKSPACE_NAME"; then
    echo "workspace-setup: workspace name $WORKSPACE_NAME already belongs to another path" >&2
    echo "workspace-setup: choose a unique persistent agent label instead of adding numeric suffixes" >&2
    restore_stage
    exit 1
fi

if ! jj -R "$RIG_ROOT" workspace add --name "$WORKSPACE_NAME" "$WT" -r "$REVSET" --sparse-patterns full; then
    echo "workspace-setup: failed to create jj workspace at $WT from $RIG_ROOT (revset $REVSET)" >&2
    restore_stage
    exit 1
fi

# Merge staged non-repo content back into the workspace.
if [ -n "$STAGE" ]; then
    find "$STAGE" -mindepth 1 -maxdepth 1 | while read -r f; do
        rel="${f#$STAGE/}"
        if [ -d "$f" ]; then
            mv "$f" "$WT/$rel" 2>/dev/null || true
        else
            if [ ! -e "$WT/$rel" ]; then
                mv "$f" "$WT/$rel" 2>/dev/null || true
            fi
        fi
    done
    rm -rf "$STAGE"
    STAGE=""
fi
trap - EXIT HUP INT TERM

write_workspace_runtime_files
install_workspace_excludes
describe_workspace_change_from_bead

if [ "$SYNC" = "--sync" ]; then
    jj -R "$WT" git fetch 2>/dev/null || true
fi

exit 0
