vim.cmd('set et sw=4 sts=-1 hid ar ai')

-- Appearance
--- Set theme
vim.cmd.colorscheme('minimal')

--- Make background transparent
vim.cmd [[
  highlight Normal guibg=none
  highlight NonText guibg=none
  highlight Normal ctermbg=none
  highlight NonText ctermbg=none
]]

--- Set relative line number
vim.wo.relativenumber = true
