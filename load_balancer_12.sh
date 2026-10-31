#!/usr/bin/env bash
# load-balancer-12: reads /proc/loadavg and compares the one-minute
# average against a configurable threshold, exiting non-zero on overload.
#
# Design choices:
#   - Threshold is passed explicitly to every function rather than held in
#     a global so callers never have to reason about hidden state.
#   - /proc/loadavg parsing is split out so it can be tested with synthetic
#     input via a function-override hook, making tests deterministic.
#   - Float comparison uses awk because Bash arithmetic is integer-only.
#   - All functions return 0 on success and non-zero on failure; overloaded
#     means exit code 1, a malformed file means exit code 2.

set -euo pipefail

# Parses the one-minute load average from a single line in /proc/loadavg
# format: "0.00 0.01 0.05 1/123 456".
#
# stdin: one line of /proc/loadavg text.
# stdout: the float value of the first field (e.g. "0.53").
# returns: 0 on success, 2 if the first field is not a valid number.
lb12_extract_loadavg() {
    local line field
    line="$(cat -)"
    # Read the first whitespace-delimited token.
    read -r field _rest <<< "$line"
    if [[ -z "$field" ]]; then
        return 2
    fi
    # Validate that field is a number using awk, which we already depend
    # on for the comparison step.
    if ! awk -v v="$field" 'BEGIN { exit !(v+0 == v) }'; then
        return 2
    fi
    printf '%s\n' "$field"
}

# Reads the real /proc/loadavg and extracts the one-minute average.
# stdout: the one-minute load float.
# returns: 0 on success, 2 if /proc/loadavg is missing or malformed.
lb12_read_system_loadavg() {
    local content
    if [[ ! -r /proc/loadavg ]]; then
        return 2
    fi
    content="$(< /proc/loadavg)"
    printf '%s\n' "$content" | lb12_extract_loadavg
}

# Compares a load value against a threshold.
# $1: loadavg value (float string).
# $2: threshold (float string).
# stdout: nothing.
# returns: 0 if loadavg <= threshold, 1 if loadavg > threshold, 2 on error.
lb12_check_overload() {
    local loadavg="$1"
    local threshold="$2"
    if [[ -z "$loadavg" || -z "$threshold" ]]; then
        return 2
    fi
    # awk handles the float comparison; returns 0 for overloaded, 1 for
    # under, 2 if either argument is non-numeric.
    awk -v l="$loadavg" -v t="$threshold" '
        BEGIN {
            if (l+0 != l || t+0 != t) exit 2
            if (l > t) exit 0
            exit 1
        }
    '
    local rc=$?
    case "$rc" in
        0) return 1 ;;  # overloaded
        1) return 0 ;;  # under or equal
        2) return 2 ;;  # error
        *) return 2 ;;
    esac
}

# Top-level entry point. Reads /proc/loadavg and exits non-zero if the
# one-minute average exceeds the threshold.
# $1: threshold (float string, e.g. "1.5").
# stdout: the measured loadavg on success.
# returns: 0 if under threshold, 1 if overloaded, 2 on read/parse error.
lb12_run() {
    local threshold="$1"
    local loadavg
    if ! loadavg="$(lb12_read_system_loadavg)"; then
        return 2
    fi
    printf '%s\n' "$loadavg"
    lb12_check_overload "$loadavg" "$threshold"
}
