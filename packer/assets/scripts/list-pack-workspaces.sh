#!/bin/sh
set -eu

PACK_FILTER=""
JSON_FILE=""

usage() {
    cat >&2 <<'EOF'
usage: list-pack-workspaces.sh [--pack <pack>] [--from-json <path>]

List existing packsmith sessions grouped by the pack workspace encoded in
their work_dir. Without --from-json, reads `gc session list --json --state all`.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --pack)
            shift
            PACK_FILTER="${1:-}"
            if [ -z "$PACK_FILTER" ]; then
                echo "list-pack-workspaces: --pack requires a value" >&2
                exit 2
            fi
            ;;
        --from-json)
            shift
            JSON_FILE="${1:-}"
            if [ -z "$JSON_FILE" ]; then
                echo "list-pack-workspaces: --from-json requires a path" >&2
                exit 2
            fi
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "list-pack-workspaces: unknown argument $1" >&2
            usage
            exit 2
            ;;
    esac
    shift
done

python3 - "$PACK_FILTER" "$JSON_FILE" <<'PY'
import json
import subprocess
import sys

pack_filter, json_file = sys.argv[1:3]

if json_file:
    with open(json_file, "r", encoding="utf-8") as f:
        raw = f.read()
else:
    result = subprocess.run(
        ["gc", "session", "list", "--json", "--state", "all"],
        text=True,
        capture_output=True,
        check=True,
    )
    raw = result.stdout

data = json.loads(raw)
if isinstance(data, dict):
    sessions = data.get("sessions") or data.get("items") or []
elif isinstance(data, list):
    sessions = data
else:
    sessions = []


def field(row, *names):
    for name in names:
        value = row.get(name)
        if value not in (None, ""):
            return str(value)
    metadata = row.get("metadata") or row.get("Metadata") or {}
    if isinstance(metadata, dict):
        for name in names:
            value = metadata.get(name)
            if value not in (None, ""):
                return str(value)
    return ""


def parse_pack_workspace(work_dir):
    parts = [p for p in work_dir.replace("\\", "/").split("/") if p]
    for index, part in enumerate(parts):
        if part != ".gc":
            continue
        if index + 4 >= len(parts):
            continue
        if parts[index + 1] != "workspaces" or parts[index + 3] != "packs":
            continue
        rig = parts[index + 2]
        pack = parts[index + 4]
        workspace = "/".join(parts[index + 5:])
        return rig, pack, workspace
    return "", "", ""


rows = []
for session in sessions:
    if not isinstance(session, dict):
        continue
    template = field(session, "template", "Template")
    if not (template == "packer.packsmith" or template.endswith("/packer.packsmith")):
        continue
    work_dir = field(session, "work_dir", "WorkDir")
    rig, pack, workspace = parse_pack_workspace(work_dir)
    if pack_filter and pack != pack_filter:
        continue
    rows.append(
        {
            "session": field(session, "id", "ID"),
            "state": field(session, "state", "State") or "-",
            "target": field(session, "alias", "Alias", "session_name", "SessionName", "name", "Name") or "-",
            "rig": rig or "-",
            "pack": pack or "-",
            "workspace": workspace or "-",
            "work_dir": work_dir or "-",
            "title": field(session, "title", "Title") or "-",
        }
    )

print("SESSION\tSTATE\tTARGET\tRIG\tPACK\tWORKSPACE\tWORKDIR\tTITLE")
for row in sorted(rows, key=lambda item: (item["pack"], item["workspace"], item["session"])):
    print(
        "\t".join(
            [
                row["session"],
                row["state"],
                row["target"],
                row["rig"],
                row["pack"],
                row["workspace"],
                row["work_dir"],
                row["title"],
            ]
        )
    )
PY
