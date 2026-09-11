[working-directory: 'nix/packages/plugins']
@plugin USER REPO *ARGS:
	npins add github "{{USER}}" "{{REPO}}" {{ARGS}}

[working-directory: 'nix/packages/plugins']
@update-plugins:
	npins update

@update-flake:
	nix flake update --commit-lock-file

@update: update-flake update-plugins

@size *ARGS:
	python3 scripts/size.py {{ARGS}}

# Install the Git hook and jj ci wrapper for size notes.
@install-size-hook:
	python3 scripts/size_note.py install

# Attach a size note to one existing Git revision.
@note-size REV="HEAD":
	python3 scripts/size_note.py record "{{REV}}"

# Backfill size notes for commits missing them, since the repo restart.
# BASE/TIP are jj revsets (git can't parse change ids like "sx"), resolved to
# commit ids here. Pass ARGS such as --include-base or --record-errors.
@backfill BASE="sx" TIP="@-" *ARGS:
	python3 scripts/size_note.py backfill \
		"$(jj log --ignore-working-copy --no-graph -r '{{BASE}}' -T commit_id)" \
		"$(jj log --ignore-working-copy --no-graph -r '{{TIP}}' -T commit_id)" \
		{{ARGS}}

@test-size:
	python3 -B -m unittest scripts/test_size.py scripts/test_size_note.py

@test:
	nix develop -c nvim --headless --noplugin -u tests/init.lua -c "lua MiniTest.run()"

@bench:
	nix shell .# nixpkgs#hyperfine -c hyperfine -w 10 -r 100 'nvim --headless +qa'

@bombadil:
  #!/usr/bin/env bash
  set -eu
  
  root=/tmp/poincare-bombadil
  
  rm -rf "$root"
  mkdir -p "$root/a" "$root/b"
  
  git -C "$root/a" init -q
  git -C "$root/b" init -q
  
  printf 'fn a() {}\n' > "$root/a/a.rs"
  printf 'fn b() {}\n' > "$root/b/b.rs"
  
  XDG_STATE_HOME="$root/state" \
  bombadil terminal test \
    --specification=tests/bombadil/pins/test.ts \
    --exit-on-violation \
    --time-limit=30s \
    --output-path="$root/out" \
    -- \
    nix run .#poincare -- \
      -c 'lua dofile("tests/bombadil/pins/oracle.lua").setup()' \
      "$root/a/a"

@bombadil-lint:
    #!/usr/bin/env bash
    set -eu

    root=/tmp/poincare-bombadil/lint

    rm -rf "$root"
    mkdir -p "$root/project/src" "$root/bin" "$root/state"

    cat > "$root/project/Cargo.toml" <<'EOF'
    [package]
    name = "bombadil-lint"
    version = "0.1.0"
    edition = "2024"

    [lib]
    path = "src/lib.rs"

    [[bin]]
    name = "bombadil-lint"
    path = "src/main.rs"
    EOF

    cat > "$root/project/src/main.rs" <<'EOF'
    fn main() {
        println!("hello");
    }
    EOF

    cat > "$root/project/src/lib.rs" <<'EOF'
    pub fn answer() -> u32 {
        42
    }
    EOF

    printf 'bombadil\n' > "$root/idle"

    XDG_STATE_HOME="$root/state" \
    bombadil terminal test \
      --specification=tests/bombadil/lint/test.ts \
      --exit-on-violation \
      --time-limit=30s \
      --output-path="$root/out" \
      -- \
      nix run .#poincare -- \
        -c 'lua dofile("tests/bombadil/lint/oracle.lua").setup()' \
        "$root/idle"
