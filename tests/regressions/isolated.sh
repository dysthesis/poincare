#!/usr/bin/env bash
# Invoked by launch.py inside fresh user/mount/PID/network/IPC/UTS namespaces.
# TEST_* and POINCARE_PACKPATH are declared in nix/shell.nix; no store path is
# inferred by scanning package names or mounting the entire host store.
set -euo pipefail
case "${1:-}" in statusline|sqlite|first_lint|first_lint_cli|gutter_saveas|gutter_superseded|vc_failure|gutter_empty) ;; *) exit 64 ;; esac
repo=$(pwd -P)
test -f "$repo/src/init.lua" && test -f "$repo/tests/regressions/init.lua"
store=$(dirname "$TEST_NVIM")
store=$(dirname "$store")
tools=("$TEST_NVIM" "$TEST_BASH" "$TEST_UTIL" "$TEST_CORE" "$MINI_TEST_RTP" "$POINCARE_PACKPATH")
path="$TEST_NVIM/bin:$TEST_BASH/bin:/bin"
case "$1" in
  sqlite) tools+=("$TEST_SQLITE"); path="$TEST_SQLITE/bin:$path" ;;
  first_lint|first_lint_cli) tools+=("$TEST_SELENE"); path="$TEST_SELENE/bin:$path" ;;
  gutter_saveas|gutter_superseded|vc_failure|gutter_empty) tools+=("$TEST_GIT"); path="$TEST_GIT/bin:$path" ;;
esac
for tool in "${tools[@]}"; do
  test -d "$tool" && test "${tool#"$store"/}" != "$tool"
done
closure=$("$TEST_NIX/bin/nix-store" -qR "${tools[@]}")
root=$(mktemp -d "${TMPDIR:-/tmp}/poincare-regress-XXXXXXXX")
cleanup() {
  umount -Rl "$root" || true
  "$TEST_PYTHON/bin/python3" -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$root"
}
trap cleanup EXIT
mount --make-rprivate /
mount -t tmpfs -o size=256m,mode=755 tmpfs "$root"
mkdir -p "$root$store" "$root"/{review/src,review/tests,dev,tmp,work,home/test,bin}
chmod 1777 "$root/tmp"
initial_file=
if [[ "$1" == first_lint_cli ]]; then
  printf 'std = "lua51"\n' > "$root/work/selene.toml"
  printf 'print(undefined_variable)\n' > "$root/work/a.lua"
  printf 'print(undefined_variable)\n' > "$root/work/b.lua"
  initial_file=/work/a.lua
fi
for src in "$repo/src" "$repo/tests"; do
  "$TEST_PYTHON/bin/python3" -c 'import os,sys; assert not any(os.path.islink(os.path.join(d,n)) for d,dirs,files in os.walk(sys.argv[1]) for n in dirs+files)' "$src"
done
for part in src tests; do
  mount --bind "$repo/$part" "$root/review/$part"
  mount -o remount,bind,ro "$root/review/$part"
done
touch "$root/dev/null"
mount --bind /dev/null "$root/dev/null"
mount -o remount,bind,ro "$root/dev/null"
while IFS= read -r dep; do
  test "${dep#"$store"/}" != "$dep"
  mkdir -p "$root$dep"
  mount --bind "$dep" "$root$dep"
  mount -o remount,bind,ro "$root$dep"
done <<< "$closure"
ln -s "$TEST_BASH/bin/bash" "$root/bin/sh"
test "$("$TEST_IP/bin/ip" -4 route show)" = ''
test "$("$TEST_IP/bin/ip" -6 route show)" = ''
"$TEST_IP/bin/ip" -o link show lo | "$TEST_BASH/bin/bash" -c 'read -r line; [[ "$line" == *"state DOWN"* ]]'
env -i HOME=/home/test XDG_CONFIG_HOME=/home/test/config XDG_CACHE_HOME=/home/test/cache XDG_DATA_HOME=/home/test/data XDG_STATE_HOME=/home/test/state TMPDIR=/tmp \
  POINCARE_PACKPATH="$POINCARE_PACKPATH" MINI_TEST_RTP="$MINI_TEST_RTP" POINCARE_TEST_CASE="$1" POINCARE_INITIAL_FILE="$initial_file" \
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null PATH="$path" \
  "$TEST_CORE/bin/chroot" "$root" "$TEST_UTIL/bin/setpriv" --bounding-set=-all --no-new-privs \
  "$TEST_BASH/bin/bash" -c '
    set -euo pipefail
    cd /review
    test ! -e /proc && test ! -e /run && test ! -e /etc
    for item in /home/*; do test "$item" = /home/test; done
    if : > /review/src/init.lua 2>/dev/null; then exit 82; fi
    if : > "$POINCARE_PACKPATH/init.lua" 2>/dev/null; then exit 82; fi
    args=()
    if [[ -n "$POINCARE_INITIAL_FILE" ]]; then args+=("$POINCARE_INITIAL_FILE"); fi
    nvim --headless --cmd '\''lua vim.opt.runtimepath:prepend("/review/src"); vim.opt.packpath:prepend(vim.env.POINCARE_PACKPATH); vim.opt.runtimepath:append(vim.env.MINI_TEST_RTP)'\'' -u /review/src/init.lua -c '\''lua dofile("/review/tests/regressions/init.lua")'\'' "${args[@]}"
  '
