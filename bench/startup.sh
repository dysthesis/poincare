#!/usr/bin/env bash
# bench/startup.sh — B1: interleaved A/B startup benchmark with a
# statistical verdict (M1, M2, M7).
#
# Both flakerefs are built (unchanged deps => byte-identical store paths;
# the delta IS the experiment), then each experiment x variant runs as ONE
# hyperfine invocation containing both arms, so runs interleave and the
# ratio comes for free.
#
# Experiments (never mixed in one invocation):
#   warm       luac bytecode cache pre-populated by hyperfine's warmup runs
#   cold-luac  --prepare wipes $XDG_CACHE_HOME/poincare before every run
#   cold-page  additionally drops the kernel page cache (needs passwordless
#              sudo; opt in with BENCH_COLD_PAGE=1)
#
# Variants: 'qa' (bare --headless +qa, M1, 100 runs) and one representative
# >=2 kLoC file per language (M2, 50 runs, warm experiment only).
#
# KNOWN BLIND SPOT: UIEnter never fires under headless hyperfine, so any
# work hanging off DeferredUIEnter costs exactly zero here. The deferred
# ledger (bench/deferred.sh, B2) owns that cost; do not read M1/M2 as
# total interactive startup.
#
# Verdict rule (B0, global): a difference is real iff the bootstrap 95% CI
# of the ratio excludes 1.0 AND |delta median| > the measured noise floor.
# Refuses to run without bench/results/noise-floor.json.
#
# Usage: bench/startup.sh <flakeref-A> <flakeref-B> [experiment...]
#   e.g. bench/startup.sh . "git+file:$PWD?rev=$(git rev-parse HEAD~1)"
set -euo pipefail

# shellcheck source=bench/env.sh
. "$(dirname "$0")/env.sh"

if [ $# -lt 2 ]; then
    echo "usage: bench/startup.sh <flakeref-A> <flakeref-B> [experiment...]" >&2
    exit 2
fi
ref_a="$1"
ref_b="$2"
shift 2
experiments=("$@")
if [ ${#experiments[@]} -eq 0 ]; then
    experiments=(warm cold-luac)
    [ "${BENCH_COLD_PAGE:-0}" = 1 ] && experiments+=(cold-page)
fi

bench_need nix hyperfine
bench_init
bench_fixtures
bench_tune

noise="$BENCH_RESULTS/noise-floor.json"
if [ ! -f "$noise" ]; then
    echo "bench: $noise missing — run bench/noise-floor.sh first (B0: no verdict without a noise floor)" >&2
    exit 2
fi

echo "bench: building A=$ref_a" >&2
out_a="$(bench_build "$ref_a")"
echo "bench: building B=$ref_b" >&2
out_b="$(bench_build "$ref_b")"
if [ "$out_a" = "$out_b" ]; then
    echo "bench: WARNING: both refs build to $out_a — this is a null experiment" >&2
fi
nvim_a="$out_a/bin/nvim"
nvim_b="$out_b/bin/nvim"

# run_pair <experiment> <variant> <runs> [nvim-extra-arg]
run_pair() {
    local experiment="$1" variant="$2" runs="$3" extra="${4:-}"
    local xdg_a xdg_b
    xdg_a="$(bench_xdg "$experiment-$variant-a")"
    xdg_b="$(bench_xdg "$experiment-$variant-b")"

    local -a args_a=(--headless) args_b=(--headless)
    if [ -n "$extra" ]; then
        args_a+=("$extra")
        args_b+=("$extra")
    fi
    args_a+=(+qa)
    args_b+=(+qa)

    local cmd_a cmd_b
    cmd_a="$(bench_cmd "$xdg_a" "$nvim_a" "${args_a[@]}")"
    cmd_b="$(bench_cmd "$xdg_b" "$nvim_b" "${args_b[@]}")"

    local -a hf=(hyperfine --style basic --warmup 20 --runs "$runs" -N
        --export-json "$BENCH_TMP/hf-$experiment-$variant.json")
    case "$experiment" in
    warm) ;;
    cold-luac)
        # NVIM_APPNAME=poincare => bytecode cache at $XDG_CACHE_HOME/poincare
        hf+=(--prepare "rm -rf '$xdg_a/cache/poincare'"
            --prepare "rm -rf '$xdg_b/cache/poincare'")
        ;;
    cold-page)
        if ! sudo -n true 2>/dev/null; then
            echo "bench: skipping cold-page (needs passwordless sudo)" >&2
            return 0
        fi
        hf+=(--prepare 'sync; echo 3 | sudo -n tee /proc/sys/vm/drop_caches >/dev/null')
        ;;
    *)
        echo "bench: unknown experiment '$experiment'" >&2
        return 2
        ;;
    esac

    local metric=M1
    [ "$variant" != qa ] && metric=M2

    echo "bench: $metric $experiment/$variant ($runs runs/arm)" >&2
    "${hf[@]}" "$cmd_a" "$cmd_b"

    bench_stats "$nvim_a" verdict \
        "$BENCH_TMP/hf-$experiment-$variant.json" "$noise" \
        "$BENCH_RESULTS/startup-$experiment-$variant.json" \
        "$metric" "$experiment" "$variant" \
        "$ref_a" "$ref_b" "$out_a" "$out_b"
}

for experiment in "${experiments[@]}"; do
    run_pair "$experiment" qa "${BENCH_M1_RUNS:-100}"
done

# M2: representative-file variants, warm only (cold variants of these mix
# luac/page effects into file-open cost and answer no extra question).
for lang_file in rust:big.rs nix:big.nix lua:big.lua python:big.py lean:big.lean; do
    lang="${lang_file%%:*}"
    file="${lang_file#*:}"
    run_pair warm "file-$lang" "${BENCH_M2_RUNS:-50}" "+edit $BENCH_ROOT/files/$file"
done

# M7 (derived): warm vs cold-luac median delta per arm = vim.loader benefit.
if [ -f "$BENCH_RESULTS/startup-warm-qa.json" ] && [ -f "$BENCH_RESULTS/startup-cold-luac-qa.json" ]; then
    bench_stats "$nvim_a" m7 \
        "$BENCH_RESULTS/startup-warm-qa.json" \
        "$BENCH_RESULTS/startup-cold-luac-qa.json" \
        "$BENCH_RESULTS/startup-m7-luac-delta.json"
fi

echo "bench: results in $BENCH_RESULTS/startup-*.json (verdicts cite $noise)" >&2
