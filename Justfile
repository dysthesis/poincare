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
