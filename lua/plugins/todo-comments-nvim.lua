require("lz.n").load({
	"todo-comments.nvim",
	event = "DeferredUIEnter",
	keys = {
		{
			"]t",
			function()
				require("todo-comments").jump_next()
			end,

			desc = "Go to next todo comment",
		},
		{
			"[t",
			function()
				require("todo-comments").jump_prev()
			end,

			desc = "Go to next todo comment",
		},
	},
	after = function()
		require("todo-comments").setup({
			keywords = {
				PERF = { color = "hint" },
			},
			colors = {
				info = { "#789978", "DiagnosticInfo" },
				hint = { "#7788AA", "DiagnosticHint" },
			},
		})
	end,
})
