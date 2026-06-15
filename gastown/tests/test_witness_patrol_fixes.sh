#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
GASTOWN="$ROOT/gastown"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

test_witness_patrol_formula_exists() {
    [[ -f "$GASTOWN/formulas/mol-witness-patrol.toml" ]] || fail "missing witness patrol formula"
}

test_witness_idle_rig_check_in_step3() {
    local formula="$GASTOWN/formulas/mol-witness-patrol.toml"

    # Verify Step 3 (burn this wisp) checks for idle rig before escalating
    grep -q 'ROUTED_WISPS=$(gc bd ready --metadata-field "gc.routed_to={{binding_prefix}}polecat"' "$formula" ||
        fail "Step 3 burn should check for routed wisps to detect idle rig"
    grep -q 'IN_PROGRESS_WISPS=$(gc bd list --status=in_progress' "$formula" ||
        fail "Step 3 burn should check for in-progress wisps to detect idle rig"
    grep -q 'if \[ "$ROUTED_WISPS" = "0" \] && \[ "$IN_PROGRESS_WISPS" = "0" \]; then' "$formula" ||
        fail "Step 3 burn should check both routed AND in-progress wisps are empty for idle detection"
}

test_witness_idle_rig_check_in_safety_mechanism() {
    local formula="$GASTOWN/formulas/mol-witness-patrol.toml"

    # Verify Safety mechanism (before step 1-4) also checks for idle rig
    # The safety mechanism should have the same idle check
    local idle_check_count
    idle_check_count=$(grep -c 'ROUTED_WISPS=' "$formula" || true)
    [[ "$idle_check_count" -ge 2 ]] || fail "idle rig check should appear in at least 2 places (Step 3 and Safety mechanism)"
}

test_witness_no_critical_alert_on_idle_rig() {
    local formula="$GASTOWN/formulas/mol-witness-patrol.toml"

    # Step 3: verify idle rig path doesn't escalate CRITICAL
    grep -q 'Rig is idle.*No current wisp to burn is expected' "$formula" ||
        fail "Step 3 should log that rig is idle without escalating CRITICAL"

    # Safety mechanism: same check
    grep -q 'Skipping burn of empty CURRENT_WISP' "$formula" ||
        fail "Safety mechanism should skip burn of empty CURRENT_WISP on idle rig"
}

test_witness_still_escalates_on_non_idle_rig() {
    local formula="$GASTOWN/formulas/mol-witness-patrol.toml"

    # Step 3: verify non-idle rig path DOES escalate CRITICAL
    grep -q 'Rig is NOT idle.*so this is a real failure' "$formula" ||
        fail "Step 3 should distinguish between idle and non-idle rigs"
    grep -q 'Cannot resolve current witness wisp' "$formula" ||
        fail "formula should escalate CRITICAL for non-idle rig with empty CURRENT_WISP"
}

test_witness_normal_burn_still_works() {
    local formula="$GASTOWN/formulas/mol-witness-patrol.toml"

    # Verify that when CURRENT_WISP IS set, normal burn still happens
    grep -q 'gc bd mol burn "$CURRENT_WISP" --force' "$formula" ||
        fail "formula should still burn CURRENT_WISP when it's set"
    grep -q 'Successfully burned wisp' "$formula" ||
        fail "formula should log successful burns"
}

test_witness_rejection_failure_still_escalates() {
    local formula="$GASTOWN/formulas/mol-witness-patrol.toml"

    # Verify genuine resolution failures (wisp set but command fails) still escalate
    grep -q 'WARNING: burn command failed' "$formula" ||
        fail "formula should have a WARNING for burn command failures"
    grep -q 'Burn command failed.*WARNING' "$formula" ||
        fail "formula should escalate burn failures"
}

# Run all tests
test_witness_patrol_formula_exists
test_witness_idle_rig_check_in_step3
test_witness_idle_rig_check_in_safety_mechanism
test_witness_no_critical_alert_on_idle_rig
test_witness_still_escalates_on_non_idle_rig
test_witness_normal_burn_still_works
test_witness_rejection_failure_still_escalates

echo "✓ All witness patrol tests passed"
