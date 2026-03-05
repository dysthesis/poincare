pcall(function()
  vim.loader.enable()
end)

local cmd = vim.cmd
local opt = vim.o

cmd('set et sw=4 sts=-1 hid ar ai')

-- Appearance
--- Set theme
cmd.colorscheme('minimal')

--- Make background transparent
cmd([[
  highlight Normal guibg=none
  highlight NonText guibg=none
  highlight Normal ctermbg=none
  highlight NonText ctermbg=none
]])

--- Set relative line number
vim.wo.relativenumber = true

--- Set colour column
opt.colorcolumn = '80'

--- Statusline

cmd([[hi StatusMode gui=bold cterm=bold]])
_G.mode_abbr = function()
  return ({
    n = 'NOR',
    no = 'NOR',
    i = 'INS',
    ic = 'INS',
    v = 'VIS',
    V = 'VIS',
    ['\22'] = 'VIS',
    R = 'REP',
    c = 'CMD',
    t = 'TER',
  })[vim.api.nvim_get_mode().mode] or vim.api.nvim_get_mode().mode:upper()
end
opt.statusline = table.concat({
  '%#StatusMode#%{v:lua.mode_abbr()}%* %t',
  '%=%y 0x%B %l:%c %p%%',
}, ' ')

-- Navigation
-- Command-line completion UI
vim.opt.wildmenu = true
vim.opt.wildmode = { 'noselect:lastused', 'full' }
vim.opt.wildoptions = { 'pum', 'fuzzy' }

-- Incrementally refresh wildmenu as you type on :, /, ?
vim.api.nvim_create_autocmd('CmdlineChanged', {
  pattern = { ':', '/', '?' },
  callback = function()
    pcall(vim.fn.wildtrigger)
  end,
})

-- Behaviour
--- Clipboard
opt.clipboard = 'unnamedplus'

opt.laststatus = 3
opt.termguicolors = true
opt.winborder = "rounded"
opt.inccommand = "split"
