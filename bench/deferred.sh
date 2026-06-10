#!/usr/bin/env bash
# bench/deferred.sh — B2 driver: deferred-cost ledger + micro-probes.
#
# Owns everything headless hyperfine can't see (DeferredUIEnter-adjacent and
# on-demand costs):
#   M3  per-plugin lz.n load time per scenario (bench/ledger.lua wraps
#       require('lz.n.loader').load; 20 runs each, 1 discarded warmup)
#   M4  LspAttach -> first DiagnosticChanged (lua-language-server from the
#       devShell; skipped cleanly when absent)
#   M5  treesitter full-reparse ns per shipped grammar (100 parses)
#   M8  RSS post-boot and at exit, per scenario
#
# Scenarios (bench/scenarios/*.lua): open-rust, insert, pick, write, dap-ui.
# Each is timed end-to-end with vim.uv.hrtime inside the child as well.
#
# Usage: bench/deferred.sh [flakeref]   (default: .)
set -euo pipefail

# shellcheck source=bench/env.sh
. "$(dirname "$0")/env.sh"

ref="${1:-$BENCH_REPO}"
runs="${BENCH_M3_RUNS:-20}"
scenarios=(open-rust insert pick write dap-ui)

bench_need nix
bench_init
bench_fixtures
bench_tune

echo "bench: building $ref#poincare" >&2
out="$(bench_build "$ref")"
nvim="$out/bin/nvim"

# run_child <xdg> <out-json|""> <+luafile target> [extra VAR=val...]
# Scenario runs inject bench/ledger.lua; its VimLeavePre owns $BENCH_OUT.
run_child() {
    local xdg="$1" bench_out="$2" target="$3"
    shift 3
    local cmd
    cmd="$(bench_cmd "$xdg" \
        BENCH_OUT="$bench_out" \
        BENCH_FILES="$BENCH_ROOT/files" \
        "$@" \
        "$nvim" --headless --cmd "luafile $BENCH_ROOT/ledger.lua" "+luafile $target")"
    eval "timeout 120 $cmd" >/dev/null 2>&1
}

# run_probe: same, WITHOUT the ledger — probes write $BENCH_OUT themselves,
# and the ledger's VimLeavePre dump would overwrite it.
run_probe() {
    local xdg="$1" bench_out="$2" target="$3"
    shift 3
    local cmd
    cmd="$(bench_cmd "$xdg" \
        BENCH_OUT="$bench_out" \
        BENCH_FILES="$BENCH_ROOT/files" \
        "$@" \
        "$nvim" --headless "+luafile $target")"
    eval "timeout 120 $cmd" >/dev/null 2>&1
}

# --- M3 + M8: scenario ledger ----------------------------------------------

for scenario in "${scenarios[@]}"; do
    echo "bench: M3 scenario $scenario ($runs runs + warmup)" >&2
    raw="$BENCH_TMP/ledger-$scenario"
    mkdir -p "$raw"
    xdg="$(bench_xdg "ledger-$scenario")"
    # one discarded warmup populates the luac cache; measured runs are warm
    run_child "$xdg" "" "$BENCH_ROOT/scenarios/$scenario.lua" ||
        echo "bench: WARNING: $scenario warmup exited non-zero" >&2
    for ((i = 1; i <= runs; i++)); do
        run_child "$xdg" "$raw/run-$i.json" "$BENCH_ROOT/scenarios/$scenario.lua" ||
            echo "bench: WARNING: $scenario run $i exited non-zero" >&2
    done
    bench_stats "$nvim" ledger "$scenario" \
        "$BENCH_RESULTS/ledger-$scenario.json" "$raw"/run-*.json
done

# --- M8 roll-up --------------------------------------------------------------

ledger_results=()
for scenario in "${scenarios[@]}"; do
    [ -f "$BENCH_RESULTS/ledger-$scenario.json" ] &&
        ledger_results+=("$BENCH_RESULTS/ledger-$scenario.json")
done
bench_stats "$nvim" rss "$BENCH_RESULTS/rss.json" "${ledger_results[@]}"

# --- M5: treesitter parse probe ----------------------------------------------

echo "bench: M5 treesitter parse probe" >&2
xdg="$(bench_xdg probe-ts)"
run_probe "$xdg" "$BENCH_TMP/tsprobe.json" "$BENCH_ROOT/scenarios/probe-treesitter.lua" \
    BENCH_TS_RUNS="${BENCH_M5_RUNS:-100}" ||
    echo "bench: WARNING: treesitter probe exited non-zero" >&2
bench_stats "$nvim" tsparse "$BENCH_TMP/tsprobe.json" "$BENCH_RESULTS/treesitter-parse.json"

# --- M4: LspAttach -> DiagnosticChanged --------------------------------------

m4_runs="${BENCH_M4_RUNS:-20}"
luals="$(command -v lua-language-server 2>/dev/null || true)"
raw="$BENCH_TMP/lsp-probe"
mkdir -p "$raw"
if [ -z "$luals" ]; then
    echo "bench: M4 skipped (lua-language-server not on PATH; enter the devShell)" >&2
    echo '{"skipped":"lua-language-server not on PATH"}' >"$raw/run-1.json"
else
    echo "bench: M4 LspAttach probe ($m4_runs runs)" >&2
    for ((i = 1; i <= m4_runs; i++)); do
        xdg="$(bench_xdg "probe-lsp-$i")"
        run_probe "$xdg" "$raw/run-$i.json" "$BENCH_ROOT/scenarios/probe-lsp.lua" \
            PATH="$(dirname "$luals")" ||
            echo "bench: WARNING: lsp probe run $i exited non-zero" >&2
    done
fi
bench_stats "$nvim" m4 "$BENCH_RESULTS/lsp-attach.json" "$raw"/run-*.json

echo "bench: results in $BENCH_RESULTS/{ledger-*,rss,treesitter-parse,lsp-attach}.json" >&2
