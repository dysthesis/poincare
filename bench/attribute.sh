#!/usr/bin/env bash
# bench/attribute.sh — single-run startup attribution (--startuptime).
#
# NOT a benchmark: one run, no statistics, no verdict. Use only after
# bench/startup.sh flags a real regression, to see where the time went.
# Baseline at audit time: init.lua ~9.1 ms self+sourced, ~14 ms to end of
# the vimrc phase, headless.
#
# Usage: bench/attribute.sh [flakeref] [file-to-open]
set -euo pipefail

# shellcheck source=bench/env.sh
. "$(dirname "$0")/env.sh"

ref="${1:-$BENCH_REPO}"
open_file="${2:-}"

bench_need nix
bench_init

out="$(bench_build "$ref")"
nvim="$out/bin/nvim"
xdg="$(bench_xdg attribute)"
log="$BENCH_TMP/startuptime.log"

# one warm-up so vim.loader bytecode cache state matches the warm experiment
eval "$(bench_cmd "$xdg" "$nvim" --headless +qa)" >/dev/null 2>&1

args=(--headless --startuptime "$log")
if [ -n "$open_file" ]; then
    args+=("+edit $open_file")
fi
args+=(+qa)
eval "$(bench_cmd "$xdg" "$nvim" "${args[@]}")" >/dev/null 2>&1

echo "== top 30 sourced scripts by self time (ms) =="
# --startuptime sourcing lines: <clock> <self+sourced> <self>: sourcing <path>
awk '$3 ~ /^[0-9]+\.[0-9]+:$/ { self = $3; sub(/:$/, "", self); printf "%10.3f  %s\n", self, substr($0, index($0, $4)) }' \
    "$log" | sort -rn | head -30

echo
echo "== last events =="
tail -5 "$log"
