local wo, g, cmd, opt = vim.wo, vim.g, vim.cmd, vim.o

--- Appearance
g.minimal_transparent = true
cmd.colorscheme("minimal")

opt.conceallevel = 2 -- How much syntax to hide
wo.relativenumber = true
opt.colorcolumn = "80"
