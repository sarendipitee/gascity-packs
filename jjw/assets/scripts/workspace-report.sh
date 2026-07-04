#!/bin/sh
# workspace-report.sh - report jjw-managed workspace health.
#
# Usage: workspace-report.sh [root]

set -eu

ROOT="${1:-${GC_JJW_REPORT_ROOT:-${GC_RIG_ROOT:-${GC_CITY_PATH:-$(pwd)}}}}"

echo "jjw workspace report"

if ! command -v jjw >/dev/null 2>&1; then
    echo "status: fail"
    echo "error: jjw is not on PATH"
    exit 1
fi

if [ ! -d "$ROOT" ]; then
    echo "root: $ROOT"
    echo "status: fail"
    echo "error: root does not exist"
    exit 1
fi

ROOT=$(CDPATH= cd -- "$ROOT" && pwd)
echo "root: $ROOT"
jjw_version=$(jjw version 2>/dev/null || true)
echo "jjw: ${jjw_version:-available}"

tmp_roots="${TMPDIR:-/tmp}/jjw-report-roots.$$"
tmp_summary="${TMPDIR:-/tmp}/jjw-report-summary.$$"
trap 'rm -f "$tmp_roots" "$tmp_summary"' EXIT HUP INT TERM

if [ -f "$ROOT/.jjw.yaml" ]; then
    printf '%s\n' "$ROOT" > "$tmp_roots"
else
    find "$ROOT" -mindepth 1 -maxdepth 3 -name .jjw.yaml -type f \
        -exec dirname {} \; | sort > "$tmp_roots"
fi

if [ ! -s "$tmp_roots" ]; then
    echo "status: warn"
    echo "warning: no jjw config found"
    exit 0
fi

grand_total=0
grand_ok=0
grand_warn=0
grand_fail=0

while read -r rig_root; do
    [ -n "$rig_root" ] || continue

    echo
    echo "rig_root: $rig_root"

    if ! report=$(cd "$rig_root" && jjw list --verbose 2>&1); then
        echo "  status: fail"
        echo "$report"
        grand_fail=$((grand_fail + 1))
        continue
    fi

    printf '%s\n' "$report"

    printf '%s\n' "$report" | awk '
        /^[[:space:]]*Status:[[:space:]]*/ {
            total++
            line = $0
            if (line ~ /\[[^]]*(conflict|stale|error|failed)[^]]*\]/) {
                fail++
            } else {
                ok++
            }
        }
        END {
            printf "total=%d ok=%d warn=%d fail=%d\n", total + 0, ok + 0, warn + 0, fail + 0
        }
    ' > "$tmp_summary"

    summary=$(cat "$tmp_summary")
    total=$(printf '%s\n' "$summary" | sed 's/.*total=\([0-9][0-9]*\).*/\1/')
    ok=$(printf '%s\n' "$summary" | sed 's/.*ok=\([0-9][0-9]*\).*/\1/')
    warn=$(printf '%s\n' "$summary" | sed 's/.*warn=\([0-9][0-9]*\).*/\1/')
    fail=$(printf '%s\n' "$summary" | sed 's/.*fail=\([0-9][0-9]*\).*/\1/')

    if [ "$total" -eq 0 ]; then
        warn=1
        echo "  warning: jjw reported no workspaces"
    fi

    echo "  summary: $summary"

    grand_total=$((grand_total + total))
    grand_ok=$((grand_ok + ok))
    grand_warn=$((grand_warn + warn))
    grand_fail=$((grand_fail + fail))
done < "$tmp_roots"

echo
echo "summary: total=$grand_total ok=$grand_ok warn=$grand_warn fail=$grand_fail"

if [ "$grand_fail" -gt 0 ]; then
    echo "status: fail"
    exit 1
fi
if [ "$grand_warn" -gt 0 ]; then
    echo "status: warn"
    exit 0
fi

echo "status: ok"
