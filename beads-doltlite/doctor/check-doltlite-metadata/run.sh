#!/usr/bin/env bash
set -euo pipefail

city_root="${GC_CITY:-${GC_CITY_PATH:-}}"
if [[ -z "$city_root" ]]; then
  city_root="$(pwd)"
fi

metadata="$city_root/.beads/metadata.json"
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
  echo "doltlite backend is not configured in city.toml; skipping metadata backend check"
  exit 0
fi

if [[ ! -f "$metadata" ]]; then
  echo "beads metadata not found at $metadata"
  echo "repair: run gc start or the beads-doltlite bootstrap for this city"
  exit 2
fi

python3 - "$metadata" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except json.JSONDecodeError as exc:
    print(f"beads metadata is not valid JSON: {path}")
    print(f"parse error: {exc}")
    sys.exit(2)
except OSError as exc:
    print(f"beads metadata could not be read: {path}")
    print(f"read error: {exc}")
    sys.exit(2)

if not isinstance(data, dict):
    print(f"beads metadata must be a JSON object: {path}")
    sys.exit(2)

errors = []
required = ("backend", "database", "dolt_database", "project_id")
for key in required:
    value = data.get(key)
    if not isinstance(value, str) or not value:
        errors.append(f"{key} must be a non-empty string")

if isinstance(data.get("backend"), str) and data["backend"] != "doltlite":
    errors.append(f'backend must be "doltlite", got {data["backend"]!r}')

for key, value in sorted(data.items()):
    if value is not None and not isinstance(value, str):
        errors.append(f"{key} must be a string or null, got {type(value).__name__}")

if errors:
    print(f"doltlite metadata contract failed: {path}")
    for err in errors:
        print(f"- {err}")
    print('repair: restore string-valued .beads/metadata.json fields or rerun beads-doltlite bootstrap')
    sys.exit(2)

print(f"doltlite metadata backend OK: {path}")
PY
