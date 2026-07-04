#!/usr/bin/env bash
# doltlite health — check doltlite database integrity and stats via bd.
set -euo pipefail

BEADS_DIR="${BEADS_DIR:-${GC_CITY_PATH:-.}/.beads}"
SCOPE_DIR="${BEADS_DIR%/.*}"
OUTPUT_FILE="${TMPDIR:-/tmp}/beads-doltlite-health-$$.json"
RAW_OUTPUT_FILE="$OUTPUT_FILE"
ERROR_FILE="${TMPDIR:-/tmp}/beads-doltlite-health-err-$$.txt"
NORMALIZED_FILE="${TMPDIR:-/tmp}/beads-doltlite-health-normalized-$$.json"

if command -v bd >/dev/null 2>&1; then
  cd "$SCOPE_DIR" || exit 1
  export BEADS_BACKEND=doltlite GC_BEADS_BACKEND=doltlite BD_NON_INTERACTIVE=1

  # Let order-level context deadlines control total runtime.
  # A fixed shell timeout here can fire first and produce misleading
  # "context canceled" from the dispatcher while the store is still
  # making progress.
  status=0
  if [ -n "${GC_DOLTLITE_HEALTH_TIMEOUT:-}" ]; then
    if command -v timeout >/dev/null 2>&1; then
      timeout "$GC_DOLTLITE_HEALTH_TIMEOUT" bd status --json >"$OUTPUT_FILE" 2>&1 || status=$?
    else
      bd status --json >"$OUTPUT_FILE" 2>&1 || status=$?
    fi
  else
    bd status --json >"$OUTPUT_FILE" 2>&1 || status=$?
  fi

  if [ "$status" -ne 0 ]; then
    cat "$OUTPUT_FILE"
    rm -f "$RAW_OUTPUT_FILE" "$OUTPUT_FILE" "$ERROR_FILE" "$NORMALIZED_FILE"
    exit "$status"
  fi

  if [ -f "$OUTPUT_FILE" ]; then
    if command -v awk >/dev/null 2>&1; then
      awk 'seen || /^[[:space:]]*\{/ { seen=1; print }' "$OUTPUT_FILE" >"$NORMALIZED_FILE"
      if [ -s "$NORMALIZED_FILE" ]; then
        OUTPUT_FILE="$NORMALIZED_FILE"
      fi
    fi
    if command -v jq >/dev/null 2>&1; then
      jq '.ok = (if has("error") then false else true end) | .schema_version = ( .schema_version // 1 )' "$OUTPUT_FILE"
    elif [ -x /usr/bin/jq ]; then
      /usr/bin/jq '.ok = (if has("error") then false else true end) | .schema_version = ( .schema_version // 1 )' "$OUTPUT_FILE"
    elif command -v python3 >/dev/null 2>&1; then
      python3 - "$OUTPUT_FILE" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)
if "ok" not in payload:
    payload["ok"] = not bool(payload.get("error"))
if "schema_version" not in payload:
    payload["schema_version"] = 1
print(json.dumps(payload, separators=(",", ":")))
PY
    elif [ -x /usr/bin/python3 ]; then
      /usr/bin/python3 - "$OUTPUT_FILE" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)
if "ok" not in payload:
    payload["ok"] = not bool(payload.get("error"))
if "schema_version" not in payload:
    payload["schema_version"] = 1
print(json.dumps(payload, separators=(",", ":")))
PY
    else
      awk_cmd=""
      if [ -x /usr/bin/awk ]; then
        awk_cmd=/usr/bin/awk
      elif [ -x /bin/awk ]; then
        awk_cmd=/bin/awk
      elif command -v awk >/dev/null 2>&1; then
        awk_cmd=awk
      fi
      if [ -n "${awk_cmd:-}" ]; then
        "$awk_cmd" '\
NR == 1 {
  if ($0 ~ /"ok"[[:space:]]*:/) {
    print $0
    next
  }
  has_schema_version = ($0 ~ /"schema_version"[[:space:]]*:/)
  if ($0 ~ /^[[:space:]]*\{[[:space:]]*$/) {
    if (has_schema_version) {
      print "{\"ok\":true,"
    } else {
      print "{\"ok\":true,\"schema_version\":1,"
    }
    next
  }
  if (has_schema_version) {
    sub(/^[[:space:]]*\{/, "{\"ok\":true,", "")
  } else {
    sub(/^[[:space:]]*\{/, "{\"ok\":true,\"schema_version\":1,", "")
  }
  print
  next
}
1
' "$OUTPUT_FILE"
      else
        cat "$OUTPUT_FILE"
      fi
    fi
  fi

  rm -f "$RAW_OUTPUT_FILE" "$OUTPUT_FILE" "$ERROR_FILE" "$NORMALIZED_FILE"
  exit 0
else
  echo '{"ok":false,"error":"bd CLI not found","schema_version":1}'
  rm -f "$RAW_OUTPUT_FILE" "$OUTPUT_FILE" "$ERROR_FILE" "$NORMALIZED_FILE"
  exit 1
fi
