# load-balancer-12

Reads `/proc/loadavg`, extracts the one-minute average, and exits non-zero when it exceeds a caller-supplied threshold.

## Usage

```bash
source load_balancer_12.sh

# Exit 1 if the one-minute load exceeds 1.5, exit 0 otherwise.
if lb12_run 1.5; then
    echo "load is within budget"
else
    rc=$?
    echo "overload or error (rc=$rc)"
fi

# Use the pieces directly:
loadavg=$(lb12_read_system_loadavg)        # reads /proc/loadavg
lb12_check_overload "$loadavg" 2.0         # returns 0 if under, 1 if over, 2 on error
printf '0.53 0.40 0.30 1/100 200\n' | lb12_extract_loadavg   # prints "0.53"
```

## Exported functions

| Function | Arguments | Returns | Notes |
|---|---|---|---|
| `lb12_run` | threshold (float) | 0 under, 1 overloaded, 2 error | Prints the measured loadavg to stdout. |
| `lb12_read_system_loadavg` | none | 0 on success, 2 on error | Prints the one-minute average. Reads `/proc/loadavg`. |
| `lb12_check_overload` | loadavg, threshold | 0 under-or-equal, 1 over, 2 error | Pure comparison, no I/O. |
| `lb12_extract_loadavg` | reads one line on stdin | 0 on success, 2 on error | Prints the first field. |

## Why

Cron jobs and batch schedulers often need to bail out when a machine is already saturated. Polling `/proc/loadavg` directly is simple, but every script ends up rewriting the same `awk` one-liner and getting the comparison backwards. This library centralises that logic with clear exit codes: `0` means "proceed", `1` means "overloaded", `2` means "could not read or parse". The trade-off is that it only looks at the one-minute average — if you need a sustained-load signal, combine this with your own timer.

## Edge cases

The threshold comparison treats `loadavg == threshold` as not overloaded (exit 0). If you need strict overload at equality, compare against a slightly lower threshold. Float parsing relies on `awk`'s numeric coercion; values like `inf` or `nan` are rejected as non-numeric. On systems without `/proc/loadavg` (non-Linux), `lb12_read_system_loadavg` and `lb12_run` return exit code 2.
