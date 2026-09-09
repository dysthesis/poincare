[working-directory: 'nix/packages/plugins']
@plugin USER REPO *ARGS:
	npins add github "{{USER}}" "{{REPO}}" {{ARGS}}

[working-directory: 'nix/packages/plugins']
@update:
	npins update

@size *ARGS:
	python3 scripts/size.py {{ARGS}}

# Install the Git hook and jj ci wrapper for size notes.
@install-size-hook:
	python3 scripts/size_note.py install

# Attach a size note to one existing Git revision.
@note-size REV="HEAD":
	python3 scripts/size_note.py record "{{REV}}"

@test-size:
	python3 -m unittest scripts/test_size.py scripts/test_size_note.py
