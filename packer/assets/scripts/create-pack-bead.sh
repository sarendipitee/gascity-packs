#!/bin/sh
set -eu

if [ -n "${TMPDIR:-}" ]; then
    if [ ! -d "$TMPDIR" ] || [ ! -w "$TMPDIR" ]; then
        unset TMPDIR
    fi
fi

usage() {
    cat >&2 <<'EOF'
usage: create-pack-bead.sh --pack <pack> --title <title> [options]

Create a pack-routed implementation bead and sling it to packsmith.

Options:
  --pack <name>              Pack route key, for example jj-hunk
  --pack-root <path>         Pack directory relative to rig root (default: pack)
  --workspace <name>         Named workspace under the pack to reuse
  --task-workspace           Create a workspace named from the child bead id/title
  --title <title>            Child bead title
  --description <text>       Child bead description
  --description-file <path>  Read child bead description from file
  --acceptance <text>        Acceptance criteria
  --parent <bead-id>         Parent/router bead
  --target <agent>           Sling target (default: <rig>/packer.packsmith)
  --dry-run                  Print commands without creating or slinging
EOF
}

PACK=""
PACK_ROOT=""
WORKSPACE=""
TASK_WORKSPACE=""
TITLE=""
DESCRIPTION=""
DESCRIPTION_FILE=""
ACCEPTANCE=""
PARENT=""
TARGET=""
DRY_RUN=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --pack)
            PACK="${2:-}"
            shift 2
            ;;
        --pack=*)
            PACK="${1#--pack=}"
            shift
            ;;
        --pack-root)
            PACK_ROOT="${2:-}"
            shift 2
            ;;
        --pack-root=*)
            PACK_ROOT="${1#--pack-root=}"
            shift
            ;;
        --workspace)
            WORKSPACE="${2:-}"
            shift 2
            ;;
        --workspace=*)
            WORKSPACE="${1#--workspace=}"
            shift
            ;;
        --task-workspace)
            TASK_WORKSPACE=1
            shift
            ;;
        --title)
            TITLE="${2:-}"
            shift 2
            ;;
        --title=*)
            TITLE="${1#--title=}"
            shift
            ;;
        --description)
            DESCRIPTION="${2:-}"
            shift 2
            ;;
        --description=*)
            DESCRIPTION="${1#--description=}"
            shift
            ;;
        --description-file)
            DESCRIPTION_FILE="${2:-}"
            shift 2
            ;;
        --description-file=*)
            DESCRIPTION_FILE="${1#--description-file=}"
            shift
            ;;
        --acceptance)
            ACCEPTANCE="${2:-}"
            shift 2
            ;;
        --acceptance=*)
            ACCEPTANCE="${1#--acceptance=}"
            shift
            ;;
        --parent)
            PARENT="${2:-}"
            shift 2
            ;;
        --parent=*)
            PARENT="${1#--parent=}"
            shift
            ;;
        --target)
            TARGET="${2:-}"
            shift 2
            ;;
        --target=*)
            TARGET="${1#--target=}"
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "create-pack-bead: unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

case "$PACK" in
    ""|.*|*/*|*' '*)
        echo "create-pack-bead: invalid or missing --pack: $PACK" >&2
        exit 2
        ;;
esac
if [ -z "$TITLE" ]; then
    echo "create-pack-bead: missing --title" >&2
    exit 2
fi
if [ -z "$PACK_ROOT" ]; then
    PACK_ROOT="$PACK"
fi
case "$WORKSPACE" in
    ""|*[!A-Za-z0-9._-]*|.|..)
        if [ -n "$WORKSPACE" ]; then
            echo "create-pack-bead: invalid --workspace: $WORKSPACE" >&2
            exit 2
        fi
        ;;
esac
if [ -n "$WORKSPACE" ] && [ -n "$TASK_WORKSPACE" ]; then
    echo "create-pack-bead: --workspace and --task-workspace are mutually exclusive" >&2
    exit 2
fi

RIG_NAME="${GC_RIG:-}"
if [ -z "$RIG_NAME" ] && [ -n "${GC_RIG_ROOT:-}" ]; then
    RIG_NAME=$(basename "$GC_RIG_ROOT")
fi
if [ -z "$RIG_NAME" ]; then
    RIG_NAME=$(basename "$(pwd -P)")
fi
if [ -z "$TARGET" ]; then
    TARGET="$RIG_NAME/packer.packsmith"
fi

metadata_file=$(mktemp)
trap 'rm -f "$metadata_file"' EXIT HUP INT TERM
python3 - "$metadata_file" "$PACK" "$PACK_ROOT" "$TARGET" "$WORKSPACE" <<'PY'
import json
import sys

path, pack, pack_root, target, workspace = sys.argv[1:6]
metadata = {
    "gc.pack": pack,
    "gc.pack_root": pack_root,
    "gc.formula": "mol-packer-work",
    "gc.route_target": target,
}
if workspace:
    metadata["gc.pack_workspace"] = workspace
with open(path, "w", encoding="utf-8") as f:
    json.dump(metadata, f, sort_keys=True)
PY

set -- create "$TITLE" --metadata "@$metadata_file" --silent
if [ -n "$DESCRIPTION_FILE" ]; then
    set -- "$@" --body-file "$DESCRIPTION_FILE"
elif [ -n "$DESCRIPTION" ]; then
    set -- "$@" --description "$DESCRIPTION"
fi
if [ -n "$ACCEPTANCE" ]; then
    set -- "$@" --acceptance "$ACCEPTANCE"
fi
if [ -n "$PARENT" ]; then
    set -- "$@" --parent "$PARENT"
fi

if [ -n "$DRY_RUN" ]; then
    printf 'bd'
    printf ' %s' "$@"
    printf '\n'
    if [ -n "$TASK_WORKSPACE" ]; then
        printf 'bd update <child-bead-id> --set-metadata gc.pack_workspace=<child-bead-id>-<title-slug>\n'
    fi
    printf 'gc sling %s <child-bead-id> --on mol-packer-work --nudge\n' "$TARGET"
    printf 'metadata: '
    cat "$metadata_file"
    printf '\n'
    exit 0
fi

child_id=$(bd "$@")
if [ -n "$TASK_WORKSPACE" ]; then
    task_workspace=$(python3 - "$child_id" "$TITLE" <<'PY'
import sys

def safe_path_slug(value, max_len):
    value = value.strip().lower()
    out = []
    last_dash = False
    for ch in value:
        if "a" <= ch <= "z" or "0" <= ch <= "9":
            token = ch
        else:
            token = "-"
        if token == "-":
            if not out or last_dash:
                continue
            last_dash = True
        else:
            last_dash = False
        out.append(token)
        if max_len > 0 and len(out) >= max_len:
            break
    return "".join(out).strip("-")

child_id, title = sys.argv[1:3]
id_slug = safe_path_slug(child_id, 32)
title_slug = safe_path_slug(title, 72)
if id_slug and title_slug:
    print(f"{id_slug}-{title_slug}")
elif id_slug:
    print(id_slug)
else:
    print(title_slug)
PY
)
    bd update "$child_id" --set-metadata "gc.pack_workspace=$task_workspace"
fi
gc sling "$TARGET" "$child_id" --on mol-packer-work --nudge

if [ -n "$PARENT" ]; then
    bd note "$PARENT" "Created pack-routed child $child_id for pack $PACK -> $TARGET using mol-packer-work."
fi

printf '%s\n' "$child_id"
