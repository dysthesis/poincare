require("lz.n").load({
	"echasnovski/mini.ai",
	event = "BufReadPost",
	after = function()
		require("mini.ai").setup()
	end,
})
