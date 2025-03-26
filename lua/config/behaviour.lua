-- Set to true if you have a Nerd Font installed and selected in the terminal
vim.g.have_nerd_font = true
vim.opt.compatible = false

vim.opt.colorcolumn = '100'

-- [[ Setting options ]]
-- See `:help vim.opt`
-- NOTE: You can change these options as you wish!
--  For more options, you can see `:help option-list`

-- Enable mouse mode, can be useful for resizing splits for example!
vim.opt.mouse = 'a'

-- Don't show the mode, since it's already in the status line
vim.opt.showmode = false

-- Sync clipboard between OS and Neovim.
--  Remove this option if you want your OS clipboard to remain independent.
--  See `:help 'clipboard'`
vim.opt.clipboard = 'unnamedplus'

-- Enable break indent
vim.opt.breakindent = true

-- Save undo history
vim.opt.undofile = true

-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.opt.ignorecase = true
vim.opt.smartcase = true

vim.opt.smartindent = true

vim.opt.showmode = false -- Dont show mode since we have a statusline
vim.opt.sidescrolloff = 8 -- Columns of context
vim.opt.signcolumn = 'yes' -- Always show the signcolumn, otherwise it would shift the text each time
vim.opt.termguicolors = true
vim.opt.wrap = false

-- Decrease update time
vim.opt.updatetime = 250

-- Use rg
vim.o.grepprg = [[rg --glob "!.git" --no-heading --vimgrep --follow $*]]
vim.opt.grepformat = vim.opt.grepformat ^ { '%f:%l:%c:%m' }

vim.opt.jumpoptions = 'view'

vim.opt.pumblend = 10
vim.opt.pumheight = 10
vim.opt.scrolloff = 4
vim.opt.shiftround = true
vim.opt.sessionoptions = { 'buffers', 'curdir', 'tabpages', 'winsize', 'help', 'globals', 'skiprtp', 'folds' }

vim.o.softtabstop = 2
vim.o.tabstop = 2
vim.o.shiftwidth = 2

-- Fold by treesitter expression
vim.opt.smoothscroll = true
vim.opt.foldexpr = "v:lua.require'utils.folding'.foldexpr()"
vim.opt.foldmethod = 'expr'
vim.opt.foldtext = ''
vim.opt.foldlevel = 99
vim.opt.expandtab = true -- Use spaces instead of tabs
vim.o.fillchars = 'eob: ,fold: ,foldopen:,foldsep: ,foldclose:'

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
