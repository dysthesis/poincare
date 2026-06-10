#!/usr/bin/env bash
# bench/noise-floor.sh — B0: measure this machine's measurement noise.
#
# Benchmarks the SAME store path as two interleaved hyperfine arms (100 runs
# each, separate XDG sandboxes) and records median, IQR, ratio and bootstrap
# 95% CI to bench/results/noise-floor.json.
#
# Verdict rule for every A/B in this repo (global, no exceptions): a
# difference is real iff the ratio CI excludes 1.0 AND |delta median|
# exceeds the delta_median_abs_ms recorded here. bench/startup.sh refuses
# to run without this artefact.
#
# Usage: bench/noise-floor.sh [flakeref]   (default: .)
set -euo pipefail

# shellcheck source=bench/env.sh
. "$(dirname "$0")/env.sh"

ref="${1:-$BENCH_REPO}"
runs="${BENCH_NOISE_RUNS:-100}"

bench_need nix hyperfine
bench_init
bench_tune

echo "bench: building $ref#poincare" >&2
out="$(bench_build "$ref")"
nvim="$out/bin/nvim"

xdg_a="$(bench_xdg noise-a)"
xdg_b="$(bench_xdg noise-b)"
cmd_a="$(bench_cmd "$xdg_a" "$nvim" --headless +qa)"
cmd_b="$(bench_cmd "$xdg_b" "$nvim" --headless +qa)"

hyperfine \
    --style basic \
    --warmup 20 \
    --runs "$runs" \
    -N \
    --export-json "$BENCH_TMP/hyperfine.json" \
    "$cmd_a" "$cmd_b"

bench_stats "$nvim" noise "$BENCH_TMP/hyperfine.json" "$out" "$BENCH_RESULTS/noise-floor.json"
echo "bench: wrote $BENCH_RESULTS/noise-floor.json" >&2
