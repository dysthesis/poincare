[working-directory: 'nix/packages/plugins']
@plugin USER REPO *ARGS:
	npins add github "{{USER}}" "{{REPO}}" {{ARGS}}
