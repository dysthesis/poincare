local opt = vim.opt
-- Set to true if you have a Nerd Font installed and selected in the terminal
vim.g.have_nerd_font = true
opt.compatible = false

opt.colorcolumn = '100'

-- [[ Setting options ]]
-- See `:help opt`
-- NOTE: You can change these options as you wish!
--  For more options, you can see `:help option-list`

-- Enable mouse mode, can be useful for resizing splits for example!
opt.mouse = 'a'

-- Don't show the mode, since it's already in the status line
opt.showmode = false

-- Sync clipboard between OS and Neovim.
--  Remove this option if you want your OS clipboard to remain independent.
--  See `:help 'clipboard'`
opt.clipboard = 'unnamedplus'

-- Enable break indent
opt.breakindent = true

-- Save undo history
opt.undofile = true

-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
opt.ignorecase = true
opt.smartcase = true

opt.smartindent = true

opt.showmode = false -- Dont show mode since we have a statusline
opt.sidescrolloff = 8 -- Columns of context
opt.signcolumn = 'yes' -- Always show the signcolumn, otherwise it would shift the text each time
opt.termguicolors = true
opt.wrap = false

-- Decrease update time
opt.updatetime = 250

-- Use rg
vim.o.grepprg = [[rg --glob "!.git" --no-heading --vimgrep --follow $*]]
opt.grepformat = opt.grepformat ^ { '%f:%l:%c:%m' }

opt.jumpoptions = 'view'

opt.pumblend = 10
opt.pumheight = 10
opt.scrolloff = 4
opt.shiftround = true
opt.sessionoptions = {
  'buffers', -- saves all open buffers
  'curdir', -- restores current working directory
  'tabpages', -- saves the state of all tab pages
  'winsize', -- remembers the sizes of windows
  'help', -- includes any help buffers in the session
  'globals', -- saves global variables so that session-specific state is maintained
  'skiprtp', -- excludes the runtime path from the session file
  'folds', -- records the folding state of the buffer
}

opt.softtabstop = 2
opt.tabstop = 2
opt.shiftwidth = 2
opt.foldcolumn = '1'

if vim.fn.has('nvim-0.10') == 1 then
  opt.smoothscroll = true
  opt.foldexpr = "v:lua.require'utils.folding'.foldexpr()"
  opt.foldmethod = 'expr'
  opt.foldtext = ''
else
  opt.foldmethod = 'indent'
  opt.foldtext = "v:lua.require'lazyvim.util'.ui.foldtext()"
end

-- Fold by treesitter expression
opt.foldlevel = 99
opt.expandtab = true -- Use spaces instead of tabs
opt.fillchars = {
  foldopen = '',
  foldclose = '',
  fold = ' ',
  foldsep = ' ',
  diff = '╱',
  eob = ' ',
}

-- I make this typo way too much
vim.cmd('cnoreabbrev W! w!')
vim.cmd('cnoreabbrev Q! q!')
vim.cmd('cnoreabbrev Qall! qall!')
vim.cmd('cnoreabbrev Wq wq')
vim.cmd('cnoreabbrev Wa wa')
vim.cmd('cnoreabbrev wQ wq')
vim.cmd('cnoreabbrev WQ wq')
vim.cmd('cnoreabbrev W w')
vim.cmd('cnoreabbrev Q q')

vim.api.nvim_create_augroup('general', {})

vim.api.nvim_create_autocmd('BufReadPost', {
  group = 'general',
  desc = 'Restore last cursor position in file',
  callback = function()
    if vim.fn.line('\'"') > 0 and vim.fn.line('\'"') <= vim.fn.line('$') then
      vim.fn.setpos('.', vim.fn.getpos('\'"'))
    end
  end,
})

vim.api.nvim_create_autocmd({ 'VimResized' }, {
  group = 'general',
  desc = 'Resize all splits if vim was resized',
  callback = function()
    vim.cmd.tabdo('wincmd =')
  end,
})

-- let sqlite.lua (which some plugins depend on) know where to find sqlite
vim.g.sqlite_clib_path = require('luv').os_getenv('LIBSQLITE')
