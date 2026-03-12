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

--- LSP
vim.diagnostic.config {
  virtual_text = {
    format = function(diagnostic)
      local client = vim.lsp.get_client_by_id(diagnostic.source)
      local prefix = ''
      if client and client.name then
        prefix = client.name .. ': '
      elseif diagnostic.source then
        prefix = diagnostic.source .. ': '
      end
      return prefix .. diagnostic.message
    end,
  },

  underline = true,

  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = '󰅚 ',
      [vim.diagnostic.severity.WARN] = '󰀪 ',
      [vim.diagnostic.severity.INFO] = '󰋽 ',
      [vim.diagnostic.severity.HINT] = '󰌶 ',
    },

    numhl = {
      [vim.diagnostic.severity.ERROR] = 'ErrorMsg',
      [vim.diagnostic.severity.WARN] = 'WarningMsg',
    },
  },
  update_in_insert = false,
  severity_sort = true,
}

-- NOTE: Define LSPs to enable here
local lsps = {
  'lua-language-server',
  'nixd',
}

for _, lsp in ipairs(lsps) do
  if vim.fn.executable(lsp) == 1 then
    vim.lsp.enable(lsp)
  end
end

vim.api.nvim_create_autocmd('LspAttach', {
  desc = 'LSP actions',
  callback = function(event)
    vim.lsp.handlers['textDocument/hover'] = vim.lsp.with(vim.lsp.handlers.hover, {
      focusable = true,
    })
    local bufnr = event.buf
    local client = vim.lsp.get_client_by_id(event.data.client_id)

    -- Enable inlay hint
    if vim.lsp.inlay_hint then
      vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
    end
    local opts = { buffer = bufnr }

    -- Set up built-in completions
    -- require('utils.completion').setup(client, bufnr)

    -- Configure LSP-related keybinds
    -- require('lz.n').trigger_load('fzf-lua')
    -- Display documentation of the symbol under the cursor
    vim.keymap.set('n', 'K', '<cmd>lua vim.lsp.buf.hover()<cr>', opts)

    -- Jump to the definition
    vim.keymap.set('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<cr>', opts)

    -- Format current file
    vim.keymap.set({ 'n', 'x' }, 'gq', '<cmd>lua vim.lsp.buf.format({async = true})<cr>', opts)

    -- Displays a function's signature information
    vim.keymap.set('i', '<C-s>', '<cmd>lua vim.lsp.buf.signature_help()<cr>', opts)

    -- Jump to declaration
    vim.keymap.set('n', '<leader>cd', '<cmd>lua vim.lsp.buf.declaration()<cr>', opts)

    -- Lists all the implementations for the symbol under the cursor
    vim.keymap.set('n', '<leader>ci', '<cmd>lua vim.lsp.buf.implementation()<cr>', opts)

    -- Jumps to the definition of the type symbol
    vim.keymap.set('n', '<leader>ct', '<cmd>lua vim.lsp.buf.type_definition()<cr>', opts)

    -- Lists all the references
    vim.keymap.set('n', '<leader>cR', '<cmd>lua vim.lsp.buf.references()<cr>', opts)

    -- Selects a code action available at the current cursor position
    vim.keymap.set('n', '<leader>ca', '<cmd>lua vim.lsp.buf.code_action()<cr>', opts)
    -- Check if rustaceanvim is the client
    if client and client.name == 'rust-analyzer' then
      -- Set up custom keybindings for rustaceanvim
      vim.keymap.set('n', 'K', function()
        vim.cmd.RustLsp { 'hover', 'actions' }
      end, { buffer = bufnr, silent = true })
    end
  end,
})
