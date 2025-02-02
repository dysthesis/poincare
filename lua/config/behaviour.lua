-- Set to true if you have a Nerd Font installed and selected in the terminal
vim.g.have_nerd_font = true

-- [[ Setting options ]]
-- See `:help vim.opt`
-- NOTE: You can change these options as you wish!
--  For more options, you can see `:help option-list`

-- Enable mouse mode, can be useful for resizing splits for example!
vim.opt.mouse = "a"

-- Don't show the mode, since it's already in the status line
vim.opt.showmode = false

-- Sync clipboard between OS and Neovim.
--  Remove this option if you want your OS clipboard to remain independent.
--  See `:help 'clipboard'`
vim.opt.clipboard = "unnamedplus"

-- Enable break indent
vim.opt.breakindent = true

-- Save undo history
vim.opt.undofile = true

-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.opt.ignorecase = true
vim.opt.smartcase = true

vim.opt.smartindent = true

-- Decrease update time
vim.opt.updatetime = 250

-- Use rg
vim.o.grepprg = [[rg --glob "!.git" --no-heading --vimgrep --follow $*]]
vim.opt.grepformat = vim.opt.grepformat ^ { "%f:%l:%c:%m" }

vim.o.tabstop = 2
vim.o.shiftwidth = 2

-- Fold by treesitter expression
vim.opt.foldmethod = "expr"
-- vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()"
vim.opt.foldcolumn = "1"
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99
vim.opt.foldenable = true
vim.opt.foldtext = ""
-- vim.o.fillchars = "eob: ,fold: ,foldopen:,foldsep: ,foldclose:"

vim.opt.rtp:append(vim.fn.stdpath("config") .. "/queries")

-- I make this typo way too much
vim.cmd("cnoreabbrev W! w!")
vim.cmd("cnoreabbrev Q! q!")
vim.cmd("cnoreabbrev Qall! qall!")
vim.cmd("cnoreabbrev Wq wq")
vim.cmd("cnoreabbrev Wa wa")
vim.cmd("cnoreabbrev wQ wq")
vim.cmd("cnoreabbrev WQ wq")
vim.cmd("cnoreabbrev W w")
vim.cmd("cnoreabbrev Q q")

vim.api.nvim_create_augroup("general", {})

vim.api.nvim_create_autocmd("BufReadPost", {
	group = "general",
	desc = "Restore last cursor position in file",
	callback = function()
		if vim.fn.line("'\"") > 0 and vim.fn.line("'\"") <= vim.fn.line("$") then
			vim.fn.setpos(".", vim.fn.getpos("'\""))
		end
	end,
})

vim.api.nvim_create_autocmd({ "VimResized" }, {
	group = "general",
	desc = "Resize all splits if vim was resized",
	callback = function()
		vim.cmd.tabdo("wincmd =")
	end,
})
