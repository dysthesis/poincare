require('lz.n').load {
	'mini.pick',
	cmd = 'Pick',
	keys = {
		{'<leader>ff', function () MiniPick.builtin.files() end, desc = '[F]ind [F]iles'}
	},
	after = function()
		require('mini.pick').setup {
			options = {
				use_cache = true,
			},
			window = {
				prompt_prefix = '   ',
			},
		}
	end,
}
