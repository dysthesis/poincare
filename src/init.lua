local o, g = vim.o, vim.g
vim.schedule(function() end)

o.pumheight = 10 -- max height of completion menu
o.tabstop = 2
g.mapleader = " "
g.maplocalleader = "\r"

-- remove netrw banner for cleaner looking
vim.g.netrw_banner = 0

o.clipboard = "unnamedplus"
o.shiftwidth = 2
o.cursorline = true -- enable cursor line
o.termguicolors = true -- enable rgb colors
o.foldenable = true -- enable fold
o.foldlevel = 99 -- start editing with all folds opened
o.foldmethod = "expr" -- use tree-sitter for folding method
o.foldexpr = "v:lua.vim.treesitter.foldexpr()"
o.confirm = true -- show dialog for unsaved file(s) before quit
o.updatetime = 200 -- save swap file with 200ms debouncing
o.ignorecase = true -- case-insensitive search
o.smartcase = true -- , until search pattern contains upper case characters
o.smartindent = true -- auto-indenting when starting a new line
o.shiftround = true -- round indent to multiple of 'shiftwidth'
o.shiftwidth = 0 -- 0 to follow the 'tabstop' value
o.tabstop = 4 -- tab width
o.undofile = true -- enable persistent undo
o.undolevels = 10000 -- 10x more undo levels

o.list = true -- use special characters to represent things like tabs or trailing spaces
o.listchars = { -- NOTE: using `vim.opt` instead of `vim.o` to pass rich object
  tab = "▏ ",
  trail = "·",
  extends = "»",
  precedes = "«",
}

require("ui")
require("icons")
require("picker")
require("treesitter")
require("completion")
require("lsp")
require("lang").setup()
require("surround")
require("autopair")
require("pins").setup()
