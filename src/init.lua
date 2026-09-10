vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.g.mapleader = " "
vim.g.maplocalleader = "\r"
vim.schedule(function()
  vim.opt.clipboard = "unnamedplus"
end)
require("ui")
require("icons")
require("picker")
require("lang").setup()
require("lsp")
require("completion")
