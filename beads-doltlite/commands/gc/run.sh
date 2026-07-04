#!/usr/bin/env bash
# doltlite gc — remove deleted beads via bd gc.
set -euo pipefail

BEADS_DIR="${BEADS_DIR:-${GC_CITY_PATH:-.}/.beads}"
SCOPE_DIR="${BEADS_DIR%/.*}"

if command -v bd >/dev/null 2>&1; then
  cd "$SCOPE_DIR" || exit 1
  export BEADS_BACKEND=doltlite GC_BEADS_BACKEND=doltlite BD_NON_INTERACTIVE=1
  status=0
  bd gc --skip-decay --force --json 2>&1 || status=$?
  if [ "$status" -ne 0 ]; then
    echo '{"deleted_beads_removed":0,"error":"bd gc failed"}'
    exit "$status"
  fi
else
  echo '{"deleted_beads_removed":0,"error":"bd CLI not found"}'
  exit 1
fi
