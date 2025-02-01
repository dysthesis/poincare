require("lz.n").load({
	"mini-completion",
	event = "InsertEnter",
	after = function()
		require("mini.completion").setup({
			lsp_completion = {
				source_func = "omnifunc",
				auto_setup = false,
			},
			window = {
				info = { border = "solid" },
				signature = { border = "solid" },
			},
		})
	end,
})
