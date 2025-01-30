require('lz.n').load {
	'blink.cmp',
	event = 'InsertEnter',
	after = function()
		require('blink.cmp').setup {
			completion = {
				documentation = { auto_show = true, auto_show_delay_ms = 0 },
				ghost_text = { enabled = true },
			},
			signature = { enabled = true },
		}
	end,
}
