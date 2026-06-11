#!/usr/bin/env bash
# Local runner for the behavioural suite; mirrors checks.tests but keeps the
# caller's PATH so external tools (lua-language-server from the devShell) are
# visible. The hermetic gate is `nix flake check`.
#
# Usage: tests/run.sh [path-to-wrapped-nvim]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

nvim_bin="${1:-${POINCARE_NVIM:-}}"
if [ -z "$nvim_bin" ]; then
    out="$(nix build "$root#poincare" --no-link --print-out-paths)"
    nvim_bin="$out/bin/nvim"
fi

# mini.test ships only as a passthru on the package, not in the binary's
# closure; resolve it here so the suite can inject it via MINI_TEST_PATH.
mini_test_path="${MINI_TEST_PATH:-}"
if [ -z "$mini_test_path" ]; then
    mini_test_path="$(nix build "$root#poincare.miniTest" --no-link --print-out-paths)"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home" "$tmp/config" "$tmp/data" "$tmp/state" "$tmp/cache" "$tmp/run"
chmod 700 "$tmp/run"

env -i \
    HOME="$tmp/home" \
    TMPDIR="$tmp" \
    LANG=C.UTF-8 \
    PATH="$PATH" \
    XDG_CONFIG_HOME="$tmp/config" \
    XDG_DATA_HOME="$tmp/data" \
    XDG_STATE_HOME="$tmp/state" \
    XDG_CACHE_HOME="$tmp/cache" \
    XDG_RUNTIME_DIR="$tmp/run" \
    POINCARE_NVIM="$nvim_bin" \
    MINI_TEST_PATH="$mini_test_path" \
    "$nvim_bin" --headless "+luafile $root/tests/minit.lua"
