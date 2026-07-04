#!/usr/bin/env bash
set -euo pipefail

city_root="${GC_CITY:-${GC_CITY_PATH:-}}"
if [[ -z "$city_root" ]]; then
  city_root="$(pwd)"
fi

city_config="$city_root/city.toml"
if [[ ! -f "$city_config" ]]; then
  echo "city.toml not found at $city_config"
  exit 1
fi

if ! python3 - "$city_config" <<'PY'
import sys

path = sys.argv[1]
in_beads = False
configured = False
with open(path, "r", encoding="utf-8") as fh:
    for raw in fh:
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            in_beads = line == "[beads]"
            continue
        if in_beads and line.replace(" ", "") == 'backend="doltlite"':
            configured = True
            break
sys.exit(0 if configured else 1)
PY
then
  echo "doltlite backend is not configured in city.toml; skipping health check"
  exit 0
fi

if ! command -v bd >/dev/null 2>&1; then
  echo "bd CLI not found in PATH"
  exit 2
fi

out="$(mktemp)"
err="$(mktemp)"
trap 'rm -f "$out" "$err"' EXIT

status=0
(
  cd "$city_root"
  export BEADS_BACKEND=doltlite GC_BEADS_BACKEND=doltlite BD_NON_INTERACTIVE=1
  if command -v timeout >/dev/null 2>&1; then
    timeout "${GC_DOLTLITE_HEALTH_TIMEOUT:-15s}" bd status --json >"$out" 2>"$err"
  else
    bd status --json >"$out" 2>"$err"
  fi
) || status=$?

if [[ "$status" -ne 0 ]]; then
  echo "doltlite health command failed"
  sed -n '1,12p' "$out"
  sed -n '1,12p' "$err"
  exit 2
fi

python3 - "$out" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except json.JSONDecodeError as exc:
    print("doltlite health output was not valid JSON")
    print(f"parse error: {exc}")
    sys.exit(2)

if isinstance(data, dict) and data.get("error"):
    print("doltlite health reported an error")
    print(str(data["error"]))
    sys.exit(2)

print("doltlite health OK")
PY
