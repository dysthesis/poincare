require("kanagawa").setup({
	keywordStyle = { italic = false },
	-- overrides = function(colors)
	-- 	local palette = colors.palette
	-- 	return {
	-- 		String = { italic = true },
	-- 		Boolean = { fg = palette.dragonPink },
	-- 		Constant = { fg = palette.dragonPink },
	--
	-- 		Identifier = { fg = palette.dragonBlue },
	-- 		Statement = { fg = palette.dragonBlue },
	-- 		Operator = { fg = palette.dragonGray2 },
	-- 		Keyword = { fg = palette.dragonRed },
	-- 		Function = { fg = palette.dragonGreen },
	--
	-- 		Type = { fg = palette.dragonYellow },
	--
	-- 		Special = { fg = palette.dragonOrange },
	--
	-- 		["@lsp.typemod.function.readonly"] = { fg = palette.dragonBlue },
	-- 		["@variable.member"] = { fg = palette.dragonBlue },
	-- 	}
	-- end,
})
vim.cmd("colorscheme kanagawa-dragon")
