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
opt.wrap = true

-- Decrease update time
opt.updatetime = 250

-- Use rg
vim.o.grepprg = [[rg --glob "!.git" --no-heading --vimgrep --follow $*]]
opt.grepformat = opt.grepformat ^ { '%f:%l:%c:%m' }
vim.o.wildoptions = 'fuzzy,pum,tagfile'
vim.bo.omnifunc = 'v:lua.vim.lsp.omnifunc'
vim.opt.completeopt = { 'menu', 'menuone', 'noselect' }
pcall(function()
  vim.opt.completeopt:append('popup')
end)
pcall(function()
  vim.opt.completeopt:append('fuzzy')
end)

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
if vim.fn.has('nvim-0.10') == 1 then
  vim.opt.foldcolumn = '1'
else
  vim.opt.foldcolumn = 1
end

if vim.fn.has('nvim-0.10') == 1 then
  opt.smoothscroll = true
  opt.foldtext = ''
else
  opt.foldmethod = 'indent'
end

-- Fold by treesitter expression
do
  local zig_folds = [[
    ;; Match the { ... } block whose *parent* is a function-like node.
    ((block) @fold
      (#has-parent? @fold "function_declaration"))

    ;; Back-compat for parsers that name it `fn_decl`.
    ((block) @fold
      (#has-parent? @fold "fn_decl"))
  ]]

  require('vim.treesitter.query').set('zig', 'folds', zig_folds)

  require('vim.treesitter.query').set(
    'rust',
    'folds',
    [[
  (block) @fold
  (#has-parent? @fold "function_item")
]]
  )

  require('vim.treesitter.query').set(
    'c',
    'folds',
    [[
    (function_definition
      body: (compound_statement) @fold)
    ]]
  )
end
vim.wo.foldmethod = 'expr'
vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
-- opt.foldmethod = 'expr'
-- opt.foldexpr = 'nvim_treesitter#foldexpr()'
vim.opt.foldenable = true
vim.opt.foldlevel = 0 -- everything eligible is closed
vim.opt.foldlevelstart = 0
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

vim.filetype.add { extension = { thy = 'isabelle' } }
local isabelle_native = require('config.isabelle')
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'isabelle',
  callback = function(args)
    if vim.b[args.buf].isabelle_lsp_started then
      return
    end
    vim.b[args.buf].isabelle_lsp_started = true
    isabelle_native.start {
      isabelle_path = vim.g.isabelle_path,
      vsplit = true,
      unicode_symbols_output = true,
      unicode_symbols_edits = true,
      hl_group_map = {
        ['background_unprocessed1'] = false,
        ['background_running1'] = false,
        ['background_canceled'] = false,
        ['background_bad'] = false,
        ['background_intensify'] = false,
        ['background_markdown_bullet1'] = 'markdownH1',
        ['background_markdown_bullet2'] = 'markdownH2',
        ['background_markdown_bullet3'] = 'markdownH3',
        ['background_markdown_bullet4'] = 'markdownH4',
        ['foreground_quoted'] = false,
        ['text_main'] = 'Normal',
        ['text_quasi_keyword'] = 'Keyword',
        ['text_free'] = 'Function',
        ['text_bound'] = 'Identifier',
        ['text_inner_numeral'] = false,
        ['text_inner_quoted'] = 'String',
        ['text_comment1'] = 'Comment',
        ['text_comment2'] = false, -- seems to not exist in the LSP
        ['text_comment3'] = false,
        ['text_dynamic'] = false,
        ['text_class_parameter'] = false,
        ['text_antiquote'] = 'Comment',
        ['text_raw_text'] = 'Comment',
        ['text_plain_text'] = 'String',
        ['text_overview_unprocessed'] = false,
        ['text_overview_running'] = 'Bold',
        ['text_overview_error'] = false,
        ['text_overview_warning'] = false,
        ['dotted_writeln'] = false,
        ['dotted_warning'] = 'DiagnosticWarn',
        ['dotted_information'] = false,
        ['spell_checker'] = 'Underlined',
        ['text_inner_cartouche'] = false,
        ['text_var'] = 'Function',
        ['text_skolem'] = 'Identifier',
        ['text_tvar'] = 'Type',
        ['text_tfree'] = 'Type',
        ['text_operator'] = 'Function',
        ['text_improper'] = 'Keyword',
        ['text_keyword3'] = 'Keyword',
        ['text_keyword2'] = 'Keyword',
        ['text_keyword1'] = 'Keyword',
        ['foreground_antiquoted'] = false,
      },
    }
  end,
})
-- Prefer internal engine with smarter matching
local function try(opt, val)
  pcall(function()
    vim.opt[opt]:append(val)
  end)
end
-- ensure it's a list (no-op if already)
vim.opt.diffopt = vim.opt.diffopt
try('diffopt', 'internal')
try('diffopt', 'filler')
try('diffopt', 'closeoff')
try('diffopt', 'indent-heuristic')
try('diffopt', 'algorithm:histogram')
try('diffopt', 'inline:word')
try('diffopt', 'linematch:60')
-- vertical diff is always fine
pcall(function()
  vim.opt.diffopt:append('vertical')
end)

-- Use vertical splits by default when diffing
vim.opt.diffopt:append('vertical')

-- When entering a merge (git mergetool opens files with &diff set), drop linematch to avoid misalignment
vim.api.nvim_create_autocmd('BufWinEnter', {
  callback = function()
    if vim.wo.diff then
      vim.opt_local.diffopt:remove('linematch:60')
    end
  end,
})
