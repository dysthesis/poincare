#!/usr/bin/env bash
# bench/nix-metrics.sh — P5: nix-level metrics. M6 (closure size) plus the
# per-package closure delta that pairs with every bench/startup.sh verdict.
#
# One command, two artefacts (single-line JSON, schema poincare-bench-v1):
#   bench/results/closure-size.json  M6: exact nar/closure bytes per arm
#                                    (nix path-info -s -S) + exact byte delta
#   bench/results/closure-diff.json  per-package version/size delta, B -> A
#                                    (nix store diff-closures; its sizes are
#                                    rounded and thresholded — the exact
#                                    total delta lives in closure-size.json)
#
# Arms follow the startup.sh convention: A = candidate, B = baseline, so the
# diff reads "what changed going from B to A". Both diff-closures dialects
# are parsed: upstream ("name: 1.0 → 2.0, +1.2 KiB", "∅" for absent) and
# Determinate ("name: 1.0 added, 1.2 KiB" / "1.0 removed, -1.2 KiB",
# ANSI-coloured even when piped). Unparsed lines keep their raw text.
#
# No sudo, no tuning, no hyperfine: nothing here is timed, so the B0
# noise-floor rule does not apply. Safe on shared CI runners.
#
# Usage: bench/nix-metrics.sh <flakeref-A> <flakeref-B>
#   e.g. bench/nix-metrics.sh . "git+file:$PWD?rev=$(git rev-parse HEAD~1)"
# Internal: bench/nix-metrics.sh --parse-diff < diff-closures-output
#   emits only the "packages" JSON array (parser self-test / CI debugging).
set -euo pipefail

# shellcheck source=bench/env.sh
. "$(dirname "$0")/env.sh"

json_str() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    printf '%s' "$s"
}

# "4.7 MiB" / "+120.4 KiB" / "-273.1 KiB" -> signed bytes (rounded).
size_to_bytes() {
    awk -v s="$1" 'BEGIN {
        split(s, p, " ")
        m = 1
        if (p[2] == "KiB") m = 1024
        else if (p[2] == "MiB") m = 1048576
        else if (p[2] == "GiB") m = 1073741824
        else if (p[2] == "TiB") m = 1099511627776
        printf "%.0f", p[1] * m
    }'
}

# stdin: raw diff-closures output. stdout: JSON array of
# {package, before, after, size_delta, size_delta_bytes_approx, raw}.
parse_diff() {
    local size_re='^[+-]?[0-9]+(\.[0-9]+)? ([KMGT]i)?B$'
    local out="" line name rest before after size last obj
    while IFS= read -r line; do
        line="$(printf '%s' "$line" | sed 's/\x1b\[[0-9;]*m//g')"
        [ -n "$line" ] || continue
        name="${line%%: *}"
        rest="${line#*: }"
        before="" after="" size=""
        last="${rest##*, }"
        if [[ $last =~ $size_re ]]; then
            size="$last"
            rest="${rest%, *}"
        fi
        case "$rest" in
        *' → '*)
            before="${rest%% → *}"
            after="${rest#* → }"
            ;;
        *' added') after="${rest% added}" ;;
        *' removed') before="${rest% removed}" ;;
        *) ;; # unrecognised shape: raw only
        esac
        [ "$before" = '∅' ] && before=""
        [ "$after" = '∅' ] && after=""

        obj="{\"package\":\"$(json_str "$name")\""
        if [ -n "$before" ]; then
            obj+=",\"before\":\"$(json_str "$before")\""
        else
            obj+=',"before":null'
        fi
        if [ -n "$after" ]; then
            obj+=",\"after\":\"$(json_str "$after")\""
        else
            obj+=',"after":null'
        fi
        if [ -n "$size" ]; then
            obj+=",\"size_delta\":\"$size\""
            obj+=",\"size_delta_bytes_approx\":$(size_to_bytes "$size")"
        else
            obj+=',"size_delta":null,"size_delta_bytes_approx":null'
        fi
        obj+=",\"raw\":\"$(json_str "$line")\"}"
        out+="${out:+,}$obj"
    done
    printf '[%s]' "$out"
}

if [ "${1:-}" = --parse-diff ]; then
    parse_diff
    echo
    exit 0
fi

if [ $# -ne 2 ]; then
    echo "usage: bench/nix-metrics.sh <flakeref-A> <flakeref-B>" >&2
    exit 2
fi
ref_a="$1"
ref_b="$2"

bench_need nix
bench_init

echo "bench: building A=$ref_a" >&2
out_a="$(bench_build "$ref_a")"
echo "bench: building B=$ref_b" >&2
out_b="$(bench_build "$ref_b")"
if [ "$out_a" = "$out_b" ]; then
    echo "bench: WARNING: both refs build to $out_a — this is a null experiment" >&2
fi

read -r _ nar_a closure_a <<<"$(nix path-info -s -S "$out_a")"
read -r _ nar_b closure_b <<<"$(nix path-info -s -S "$out_b")"
now="$(date -u +%FT%TZ)"

arm_a="{\"flakeref\":\"$(json_str "$ref_a")\",\"store_path\":\"$(json_str "$out_a")\""
arm_b="{\"flakeref\":\"$(json_str "$ref_b")\",\"store_path\":\"$(json_str "$out_b")\""

printf '%s\n' "{\"unit\":\"bytes\",\"generated_at\":\"$now\",\"metric_id\":\"M6\",\"schema\":\"poincare-bench-v1\",\"arms\":{\"a\":$arm_a,\"nar_bytes\":$nar_a,\"closure_bytes\":$closure_a},\"b\":$arm_b,\"nar_bytes\":$nar_b,\"closure_bytes\":$closure_b}},\"delta_closure_bytes\":$((closure_a - closure_b))}" \
    >"$BENCH_RESULTS/closure-size.json"
echo "bench: wrote $BENCH_RESULTS/closure-size.json (M6)" >&2

packages="$(nix store diff-closures "$out_b" "$out_a" | parse_diff)"
printf '%s\n' "{\"unit\":\"bytes\",\"generated_at\":\"$now\",\"schema\":\"poincare-bench-v1\",\"direction\":\"b_to_a\",\"arms\":{\"a\":$arm_a},\"b\":$arm_b}},\"packages\":$packages}" \
    >"$BENCH_RESULTS/closure-diff.json"
echo "bench: wrote $BENCH_RESULTS/closure-diff.json" >&2
