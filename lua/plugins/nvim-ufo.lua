require("lz.n").load({
	"nvim-ufo",
	keys = {
		{
			"zR",
			function()
				require("ufo").openAllFolds()
			end,
			desc = "Open all folds",
		},
		{
			"zM",
			function()
				require("ufo").closeAllFolds()
			end,
			desc = "Open all folds",
		},
	},
})
