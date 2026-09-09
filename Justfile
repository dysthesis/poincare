[working-directory: 'nix/packages/plugins']
@plugin USER REPO *ARGS:
	npins add github "{{USER}}" "{{REPO}}" {{ARGS}}

@size *ARGS:
	python3 scripts/size.py {{ARGS}}

@test-size:
	python3 -m unittest scripts/test_size.py
