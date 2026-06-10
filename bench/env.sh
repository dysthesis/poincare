# bench/env.sh — sourced library for the benchmark harness (P4). Not executable.
#
# Provides: dependency checks, flakeref builds, per-arm XDG sandboxes, CPU
# pinning, fixture generation, and sudo-gated machine tuning (governor,
# turbo, SMT). Tuning is best-effort and skippable: set BENCH_NO_TUNE=1, or
# lack passwordless sudo, and the scripts run untuned with a warning — the
# measured noise floor (bench/noise-floor.sh) is what absorbs an untuned
# machine, per the global verdict rule.
#
# Tunables (environment):
#   BENCH_CPU      core to pin benchmarked processes to (default 3)
#   BENCH_NO_TUNE  1 = never touch governor/turbo/SMT
#
# shellcheck shell=bash

BENCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_REPO="$(dirname "$BENCH_ROOT")"
BENCH_RESULTS="$BENCH_ROOT/results"
BENCH_CPU="${BENCH_CPU:-3}"

bench_need() {
    local tool
    for tool in "$@"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "bench: missing dependency: $tool" >&2
            echo "hint: nix shell --inputs-from '$BENCH_REPO' nixpkgs#hyperfine nixpkgs#jq" >&2
            exit 2
        fi
    done
}

# Call once per script: temp root + cleanup trap + results dir.
bench_init() {
    BENCH_TMP="$(mktemp -d)"
    # shellcheck disable=SC2064  # expand now: cleanup must survive set -u edge cases
    trap "bench_untune; rm -rf '$BENCH_TMP'" EXIT
    mkdir -p "$BENCH_RESULTS"
}

# Fixtures are generated (gitignored); make them exist before use.
bench_fixtures() {
    if [ ! -f "$BENCH_ROOT/files/big.rs" ]; then
        "$BENCH_ROOT/files/gen.sh"
    fi
}

# bench_build <flakeref> -> store path of the poincare package.
bench_build() {
    nix build "$1#poincare" --no-link --print-out-paths
}

# bench_xdg <label> -> path of a fresh, fully isolated XDG sandbox.
bench_xdg() {
    local dir="$BENCH_TMP/$1"
    mkdir -p "$dir"/{home,tmp,config,data,state,cache,run}
    chmod 700 "$dir/run"
    printf '%s' "$dir"
}

# bench_cmd <xdg-sandbox> [VAR=val...] <argv...> -> one shell-quoted command
# string for hyperfine (-N) or eval. Hermetic env -i in the style of the
# flake checks; pinned to BENCH_CPU when taskset exists. Leading VAR=val
# words are hoisted into the env section (they must precede taskset, which
# would otherwise swallow them as its command).
bench_cmd() {
    local xdg="$1"
    shift
    local -a argv=(
        env -i
        HOME="$xdg/home"
        TMPDIR="$xdg/tmp"
        LANG=C.UTF-8
        TERM=dumb
        XDG_CONFIG_HOME="$xdg/config"
        XDG_DATA_HOME="$xdg/data"
        XDG_STATE_HOME="$xdg/state"
        XDG_CACHE_HOME="$xdg/cache"
        XDG_RUNTIME_DIR="$xdg/run"
    )
    while [ $# -gt 0 ] && [[ $1 =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
        argv+=("$1")
        shift
    done
    if command -v taskset >/dev/null 2>&1; then
        argv+=("$(command -v taskset)" -c "$BENCH_CPU")
    fi
    argv+=("$@")
    local out="" word
    for word in "${argv[@]}"; do
        out+=" $(printf '%q' "$word")"
    done
    printf '%s' "${out# }"
}

# bench_stats <nvim> <stats-args...> — run bench/stats.lua under the built
# nvim (the artefact under test doubles as the Lua interpreter), with its
# own XDG sandbox so stats runs never touch benchmark or user caches.
bench_stats() {
    local nvim="$1"
    shift
    local xdg
    xdg="$(bench_xdg stats)"
    env -i \
        HOME="$xdg/home" \
        TMPDIR="$xdg/tmp" \
        LANG=C.UTF-8 \
        TERM=dumb \
        XDG_CONFIG_HOME="$xdg/config" \
        XDG_DATA_HOME="$xdg/data" \
        XDG_STATE_HOME="$xdg/state" \
        XDG_CACHE_HOME="$xdg/cache" \
        XDG_RUNTIME_DIR="$xdg/run" \
        "$nvim" -l "$BENCH_ROOT/stats.lua" "$@"
}

_bench_sysfs_write() {
    # best-effort; callers already hold passwordless sudo
    echo "$2" | sudo -n tee "$1" >/dev/null 2>&1 || true
}

# Reduce machine noise. Saves previous state under $BENCH_TMP for
# bench_untune. Every path is optional; absence is silently skipped.
bench_tune() {
    if [ "${BENCH_NO_TUNE:-0}" = 1 ]; then
        echo "bench: tuning skipped (BENCH_NO_TUNE=1)" >&2
        return 0
    fi
    if ! sudo -n true 2>/dev/null; then
        echo "bench: no passwordless sudo; running untuned (the noise floor absorbs this)" >&2
        return 0
    fi

    local gov="/sys/devices/system/cpu/cpu$BENCH_CPU/cpufreq/scaling_governor"
    local boost="/sys/devices/system/cpu/cpufreq/boost"
    local turbo="/sys/devices/system/cpu/intel_pstate/no_turbo"
    local smt="/sys/devices/system/cpu/smt/control"

    mkdir -p "$BENCH_TMP/tune"
    if [ -r "$gov" ]; then
        cat "$gov" >"$BENCH_TMP/tune/governor"
        _bench_sysfs_write "$gov" performance
    fi
    if [ -r "$boost" ]; then
        cat "$boost" >"$BENCH_TMP/tune/boost"
        _bench_sysfs_write "$boost" 0
    fi
    if [ -r "$turbo" ]; then
        cat "$turbo" >"$BENCH_TMP/tune/no_turbo"
        _bench_sysfs_write "$turbo" 1
    fi
    if [ -r "$smt" ]; then
        cat "$smt" >"$BENCH_TMP/tune/smt"
        _bench_sysfs_write "$smt" off
    fi
    echo "bench: tuned (governor=performance, turbo off, SMT off; restored on exit)" >&2
}

bench_untune() {
    [ -d "${BENCH_TMP:-/nonexistent}/tune" ] || return 0
    sudo -n true 2>/dev/null || return 0
    [ -f "$BENCH_TMP/tune/governor" ] &&
        _bench_sysfs_write "/sys/devices/system/cpu/cpu$BENCH_CPU/cpufreq/scaling_governor" "$(cat "$BENCH_TMP/tune/governor")"
    [ -f "$BENCH_TMP/tune/boost" ] &&
        _bench_sysfs_write "/sys/devices/system/cpu/cpufreq/boost" "$(cat "$BENCH_TMP/tune/boost")"
    [ -f "$BENCH_TMP/tune/no_turbo" ] &&
        _bench_sysfs_write "/sys/devices/system/cpu/intel_pstate/no_turbo" "$(cat "$BENCH_TMP/tune/no_turbo")"
    [ -f "$BENCH_TMP/tune/smt" ] &&
        _bench_sysfs_write "/sys/devices/system/cpu/smt/control" "$(cat "$BENCH_TMP/tune/smt")"
    return 0
}
