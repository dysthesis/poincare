require("lackluster").setup({
	tweak_background = {
		normal = "none",
	},
})
local spec = require("lackluster.spec")

spec.bg("TodoBgTodo", "#7788AA")
spec.bg("TodoFgTodo", "#000000")

vim.cmd.colorscheme("lackluster-night")
