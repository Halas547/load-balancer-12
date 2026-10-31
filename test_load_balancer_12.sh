#!/usr/bin/env bash
# Tests for load-balancer-12.
# Run with: bash test_load_balancer_12.sh

set -euo pipefail

# shellcheck source=load_balancer_12.sh
source "$(dirname "$0")/load_balancer_12.sh"

passed=0
failed=0

# Assert two strings are equal. Prints TAP-like output.
# $1: expected, $2: actual, $3: description.
assert_eq() {
    local expected="$1"
    local actual="$2"
    local desc="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf 'ok %d - %s\n' "$((passed + failed + 1))" "$desc"
        passed=$((passed + 1))
    else
        printf 'not ok %d - %s\n' "$((passed + failed + 1))" "$desc"
        printf '  expected: %q\n' "$expected"
        printf '  actual:   %q\n' "$actual"
        failed=$((failed + 1))
    fi
}

# Assert a command exits with a specific code.
# $1: expected code, rest: command and args.
assert_rc() {
    local expected="$1"; shift
    local desc="$1"; shift
    local actual
    set +e
    actual="$("$@" 2>/dev/null)"
    actual=$?
    set -e
    assert_eq "$expected" "$actual" "$desc"
}

echo 'TAP version 13'

# --- lb12_extract_loadavg ---

out=$(printf '0.52 0.43 0.35 1/234 567\n' | lb12_extract_loadavg); rc=$?
assert_eq "0.52" "$out" "extract first field from valid line"
assert_eq "0" "$rc" "extract returns 0 for valid input"

out=$(printf '1.23 2.34 3.45 2/100 200\n' | lb12_extract_loadavg); rc=$?
assert_eq "1.23" "$out" "extract handles multi-digit integer part"

out=$(printf '0.00 0.00 0.00 1/1 2\n' | lb12_extract_loadavg); rc=$?
assert_eq "0.00" "$out" "extract handles zero load"
assert_eq "0" "$rc" "extract returns 0 for zero load"

assert_rc 2 "extract rejects empty stdin" bash -c 'source "'"$(dirname "$0")/load_balancer_12.sh"'"; printf "" | lb12_extract_loadavg'

assert_rc 2 "extract rejects non-numeric first field" bash -c 'source "'"$(dirname "$0")/load_balancer_12.sh"'"; printf "abc 0.1 0.2 1/1 2\n" | lb12_extract_loadavg'

# --- lb12_check_overload ---

assert_rc 0 "under threshold returns 0" lb12_check_overload 0.5 1.0
assert_rc 1 "over threshold returns 1" lb12_check_overload 2.5 1.0
assert_rc 0 "equal to threshold returns 0 (not overloaded)" lb12_check_overload 1.0 1.0
assert_rc 0 "zero load under positive threshold returns 0" lb12_check_overload 0.0 1.0
assert_rc 1 "small fractional overload returns 1" lb12_check_overload 1.001 1.0
assert_rc 2 "non-numeric load returns 2" lb12_check_overload abc 1.0
assert_rc 2 "non-numeric threshold returns 2" lb12_check_overload 1.0 xyz
assert_rc 2 "empty load returns 2" lb12_check_overload "" 1.0
assert_rc 2 "empty threshold returns 2" lb12_check_overload 1.0 ""

# --- lb12_run with injected fake ---
# We override lb12_read_system_loadavg to return a fixed value so the
# test is deterministic and does not depend on the host.
_lb12_fake_loadavg_value=""
lb12_read_system_loadavg() {
    printf '%s\n' "$_lb12_fake_loadavg_value"
}

_lb12_fake_loadavg_value="0.30"
assert_rc 0 "lb12_run under threshold returns 0" lb12_run 1.0

_lb12_fake_loadavg_value="5.00"
assert_rc 1 "lb12_run over threshold returns 1" lb12_run 1.0

_lb12_fake_loadavg_value="0.00"
assert_rc 0 "lb12_run zero load returns 0" lb12_run 0.5

# --- lb12_read_system_loadavg error path (restore real first) ---
# Use a subshell with the original source to test the real function
# against a non-existent /proc by pointing nothing there — we cannot
# easily fake /proc, so we test the extract fallback instead.
assert_rc 2 "extract on whitespace-only line returns 2" bash -c 'source "'"$(dirname "$0")/load_balancer_12.sh"'"; printf "   \n" | lb12_extract_loadavg'

echo "1..$((passed + failed))"
if [[ "$failed" -ne 0 ]]; then
    echo "# $failed failures" >&2
    exit 1
fi
echo "# all $passed tests passed"
