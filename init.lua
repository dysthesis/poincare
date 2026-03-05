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
vim.mode_abbr = function()
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
  '%#StatusMode#%{v:lua.vim.mode_abbr()}%* %t',
  '%=%y 0x%B %l:%c %p%%',
}, ' ')

-- Command-line completion UI
opt.wildmenu = true
opt.wildmode = 'longest:full,full' -- command-line completion behaviour
opt.wildoptions = 'pum,fuzzy' -- show popup menu with fuzzy matching
opt.completeopt = 'menu,menuone,popup,fuzzy' -- modern completion menu

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
opt.winborder = 'rounded'
opt.inccommand = 'split'
opt.cursorline = true -- enable cursor line
vim.g.netrw_banner = 0
