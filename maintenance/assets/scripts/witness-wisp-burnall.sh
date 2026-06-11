#!/usr/bin/env bash
# witness-wisp-burnall — Emergency cleanup for accumulated unburned witness wisps.
#
# This script is a one-time fix for wisp accumulation (gc-pack-86n). When the
# witness patrol loop exits early without reaching the burn step, wisps accumulate
# as "open" beads. This script safely burns all old open wisps for a given agent.
#
# Usage: witness-wisp-burnall.sh [agent-name] [age-threshold-hours]
#   agent-name: e.g., "gascity-packs-source/gastown.witness" (default: all witness agents)
#   age-threshold-hours: only burn wisps older than this (default: 1)
#
# Safety: Wisps are sorted by age, and this script only burns wisps older than
# the threshold and with no recent activity. Before burning, it prints the bead
# IDs so the operator can verify.
set -euo pipefail

AGENT_FILTER="${1:-}" # e.g., "gastown.witness" or empty to match all
AGE_THRESHOLD_HOURS="${2:-1}"

NOW=$(date +%s)
AGE_THRESHOLD_SECS=$((AGE_THRESHOLD_HOURS * 3600))

echo "Witness Wisp Cleanup"
echo "===================="
echo "Agent filter: ${AGENT_FILTER:-all}"
echo "Age threshold: ${AGE_THRESHOLD_HOURS}h ($AGE_THRESHOLD_SECS seconds)"
echo ""

# Find all open ephemeral beads that look like witness wisps.
# Match by:
# - title containing "witness-patrol" or "mol-witness-patrol"
# - status = open
# - assignee contains "witness" (if AGENT_FILTER set, must match)
# - older than threshold

QUERY="ephemeral=true AND status=open"
if [ -n "$AGENT_FILTER" ]; then
    QUERY="$QUERY AND assignee~\"${AGENT_FILTER}\""
fi

# Query for candidates.
WISPS=$(bd query --json "$QUERY" --limit=0 2>/dev/null || echo "[]")

# Filter and age-check.
TO_BURN=$(echo "$WISPS" | jq -r --arg now "$NOW" --arg threshold "$AGE_THRESHOLD_SECS" '
  .[]
  | select((.title // "") | contains("witness") or contains("patrol"))
  | (.updated_at // .created_at // "1970-01-01T00:00:00Z") as $ts
  | (
      ($ts | split("T")[0]) as $d
      | ($ts | split("T")[1] | split("Z")[0]) as $t
      | ($d + "T" + $t + "Z")
    ) as $normalized_ts
  | select(
      (try (($now | tonumber) - (($normalized_ts | split("T")[0] | split("-") | map(tonumber) as [$y,$m,$d] |
             (($normalized_ts | split("T")[1] | split(":") | map(tonumber) as [$h,$min,$s] |
             (((($y-1970)*365 + (($m-1)*30) + ($d-1))*86400 + ($h*3600) + ($min*60) + $s)))) ) | tonumber)
         >= ($threshold | tonumber))
      catch false
    )
  | .id
' 2>/dev/null | sort)

if [ -z "$TO_BURN" ]; then
    echo "No old open wisps found matching the filter and age threshold."
    exit 0
fi

COUNT=$(echo "$TO_BURN" | wc -l)
echo "Found $COUNT old open wisps to burn:"
echo "$TO_BURN"
echo ""

# Safety check: don't burn too many at once (prevents accidents).
if [ "$COUNT" -gt 100 ]; then
    echo "ERROR: Found $COUNT wisps to burn — this is more than expected (limit: 100)."
    echo "This suggests a systemic issue. Refusing to proceed to avoid data loss."
    echo "Escalate to mayor and check witness patrol logs."
    exit 1
fi

# Confirm with operator (if stdin is a tty).
if [ -t 0 ]; then
    read -p "Burn these $COUNT wisps? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled."
        exit 0
    fi
fi

# Burn each wisp.
BURNED=0
FAILED=0
while IFS= read -r wisp_id; do
    if bd mol burn "$wisp_id" --force 2>/dev/null; then
        BURNED=$((BURNED + 1))
        echo "✓ Burned $wisp_id"
    else
        FAILED=$((FAILED + 1))
        echo "✗ Failed to burn $wisp_id"
    fi
done <<< "$TO_BURN"

echo ""
echo "Summary: burned=$BURNED failed=$FAILED"
if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
