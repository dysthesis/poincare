vim.g.have_nerd_font = true

local o = vim.opt
o.expandtab = true
o.shiftwidth = 4
o.softtabstop = -1
o.compatible = false
o.colorcolumn = '100'
o.mouse = 'a'
o.showmode = false
o.clipboard = 'unnamedplus'
o.laststatus = 0
o.breakindent = true
o.undofile = true
o.ignorecase = true
o.smartcase = true
o.smartindent = true
o.showmode = false 
o.sidescrolloff = 8 
o.signcolumn = 'yes' 
o.termguicolors = true
o.wrap = true
o.updatetime = 250

o.grepprg = [[rg --glob "!.git" --no-heading --vimgrep --follow $*]]
o.grepformat = o.grepformat ^ { '%f:%l:%c:%m' }
o.completeopt = 'menu,menuone,noselect,popup,fuzzy'
o.wildoptions = 'fuzzy,pum,tagfile'

vim.bo.omnifunc = 'v:lua.vim.lsp.omnifunc'

o.jumpoptions = 'view'

o.pumblend = 10
o.pumheight = 10
o.scrolloff = 4
o.shiftround = true
o.sessionoptions = {
  'buffers', -- saves all open buffers
  'curdir', -- restores current working directory
  'tabpages', -- saves the state of all tab pages
  'winsize', -- remembers the sizes of windows
  'help', -- includes any help buffers in the session
  'globals', -- saves global variables so that session-specific state is maintained
  'skiprtp', -- excludes the runtime path from the session file
  'folds', -- records the folding state of the buffer
}

o.softtabstop = 2
o.tabstop = 2
o.shiftwidth = 2
o.foldcolumn = '1'

if vim.fn.has('nvim-0.10') == 1 then
  o.smoothscroll = true
  o.foldtext = ''
else
  o.foldmethod = 'indent'
  o.foldtext = "v:lua.require'lazyvim.util'.ui.foldtext()"
end

-- Fold by treesitter expression
o.foldlevel = 99
o.fillchars = {
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

-- Persist view
local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd
local view_group = augroup('auto_view', { clear = true })
autocmd({ 'BufWinLeave', 'BufWritePost', 'WinLeave' }, {
  desc = 'Save view with mkview for real files',
  group = view_group,
  callback = function(args)
    if vim.b[args.buf].view_activated then
      vim.cmd.mkview { mods = { emsg_silent = true } }
    end
  end,
})
autocmd('BufWinEnter', {
  desc = 'Try to load file view if available and enable view saving for real files',
  group = view_group,
  callback = function(args)
    if not vim.b[args.buf].view_activated then
      local filetype = vim.api.nvim_get_option_value('filetype', { buf = args.buf })
      local buftype = vim.api.nvim_get_option_value('buftype', { buf = args.buf })
      local ignore_filetypes = { 'gitcommit', 'gitrebase', 'svg', 'hgcommit' }
      if buftype == '' and filetype and filetype ~= '' and not vim.tbl_contains(ignore_filetypes, filetype) then
        vim.b[args.buf].view_activated = true
        vim.cmd.loadview { mods = { emsg_silent = true } }
      end
    end
  end,
})

-- let sqlite.lua (which some plugins depend on) know where to find sqlite
vim.g.sqlite_clib_path = require('luv').os_getenv('LIBSQLITE')

local lackluster = require('lackluster')
lackluster.setup {
  tweak_background = {
    normal = 'none',
    telescope = 'none',
    menu = 'none',
    popup = 'none',
  },
}

vim.cmd.colorscheme('lackluster-night')
vim.api.nvim_set_hl(0, 'Folded', { bg = '#191919' })
