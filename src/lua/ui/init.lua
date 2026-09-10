local wo, g, cmd, opt = vim.wo, vim.g, vim.cmd, vim.o

-- Which theme to use?
g.minimal_transparent = true -- transparent background
cmd.colorscheme("minimal")

local transparent_pmenu = {
  "Pmenu",
  "PmenuKind",
  "PmenuExtra",
  "PmenuMatch",
}

for _, group in ipairs(transparent_pmenu) do
  vim.cmd(("highlight %s guibg=NONE ctermbg=NONE"):format(group))
end

opt.conceallevel = 2 -- How much syntax to hide
wo.relativenumber = true
opt.colorcolumn = "80"

opt.statusline = "%{%v:lua.require'ui.statusline'.render()%}"

-- Some useful add-ons
require("ui.splits").setup() -- integrate splits with tmux
require("ui.vc-gutter").setup() -- show dirty changes in gutter
