pcall(function()
  vim.loader.enable()
end)

vim.cmd.filetype('plugin', 'indent', 'on')
vim.cmd.packadd('cfilter') -- Allows filtering the quickfix list with :cfdo

local cmd = vim.cmd
local opt = vim.o

-- Appearance
--- Set theme
vim.g.minimal_transparent = true
cmd.colorscheme('minimal')

--- Set relative line number
vim.wo.relativenumber = true

--- Set colour column
opt.colorcolumn = '80'

-- Avoid upcoming deprecation in vim.lsp.diagnostic.get_namespace by normalizing
-- boolean pull_id values to the string/nil forms expected in Neovim 0.14.
do
  local lsp_diagnostic = vim.lsp.diagnostic
  local original = lsp_diagnostic.get_namespace
  lsp_diagnostic.get_namespace = function(client_id, pull_id)
    if type(pull_id) == 'boolean' then
      pull_id = pull_id and 'nil' or nil
    end
    return original(client_id, pull_id)
  end
end

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
opt.wildmode = 'noselect' -- command-line completion behaviour
opt.wildoptions = 'pum,fuzzy' -- show popup menu with fuzzy matching
opt.completeopt = 'menu,menuone,popup,fuzzy,noselect' -- modern completion menu
-- Incrementally refresh wildmenu as you type on :, /, ?
vim.api.nvim_create_autocmd('CmdlineChanged', {
  pattern = { ':', '/', '?' },
  callback = function()
    pcall(vim.fn.wildtrigger)
  end,
})

-- Behaviour
opt.smartcase = true
--- Leader keys
vim.g.mapleader = vim.keycode('<space>')
vim.g.maplocalleader = vim.keycode('<cr>')
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
vim.lsp.config('*', {
  capabilities = {
    textDocument = {
      semanticTokens = {
        multilineTokenSupport = true,
      },
    },
  },
  root_markers = { '.git' },
})

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
    local bufnr = event.buf
    local client = assert(vim.lsp.get_client_by_id(event.data.client_id))

    -- Enable inlay hint
    if vim.lsp.inlay_hint then
      vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
    end

    local opts = { buffer = bufnr }
    if client:supports_method('textDocument/completion') then
      -- trigger autocompletion on EVERY keypress. May be slow!
      local chars = {}
      for i = 32, 126 do
        table.insert(chars, string.char(i))
      end
      client.server_capabilities.completionProvider.triggerCharacters = chars

      vim.lsp.completion.enable(true, client.id, event.buf, { autotrigger = true })
    end

    -- Auto-format ("lint") on save.
    -- Usually not needed if server supports "textDocument/willSaveWaitUntil".
    if
      not client:supports_method('textDocument/willSaveWaitUntil')
      and client:supports_method('textDocument/formatting')
    then
      vim.api.nvim_create_autocmd('BufWritePre', {
        group = vim.api.nvim_create_augroup('my.lsp', { clear = false }),
        buffer = event.buf,
        callback = function()
          -- TODO: Formatting function
          -- vim.lsp.buf.format { bufnr = event.buf, id = client.id, timeout_ms = 1000 }
        end,
      })
    end

    -- Display documentation of the symbol under the cursor
    vim.keymap.set('n', 'K', function()
      vim.lsp.buf.hover { focusable = true }
    end, opts)

    -- Jump to the definition
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)

    -- Format current file
    vim.keymap.set({ 'n', 'x' }, 'gq', '<cmd>lua vim.lsp.buf.format({async = true})<cr>', opts)

    -- Displays a function's signature information
    vim.keymap.set('i', '<C-s>', vim.lsp.buf.signature_help, opts)

    -- Jump to declaration
    vim.keymap.set('n', '<leader>cd', vim.lsp.buf.declaration, opts)

    -- Lists all the implementations for the symbol under the cursor
    vim.keymap.set('n', '<leader>ci', vim.lsp.buf.implementation, opts)

    -- Jumps to the definition of the type symbol
    vim.keymap.set('n', '<leader>ct', vim.lsp.buf.type_definition, opts)

    -- Lists all the references
    vim.keymap.set('n', '<leader>cR', vim.lsp.buf.references, opts)

    -- Selects a code action available at the current cursor position
    vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, opts)
    -- Check if rustaceanvim is the client
    if client and client.name == 'rust-analyzer' then
      -- Set up custom keybindings for rustaceanvim
      vim.keymap.set('n', 'K', function()
        vim.cmd.RustLsp { 'hover', 'actions' }
      end, { buffer = bufnr, silent = true })
    end
  end,
})

-- Tree-sitter
vim.api.nvim_create_autocmd('FileType', {
  callback = function(event)
    pcall(vim.treesitter.start, event.buf)
  end,
})

-- Plugins
--- Picker
require('lz.n').load {
  { 'mini.extra' },
  {
    'mini.pick',
    cmd = 'Pick',
    keys = {
      {
        '<leader>f',
        function()
          require('mini.pick').builtin.files()
        end,
        desc = 'Find [F]iles',
      },
      {
        '<leader>/',
        function()
          require('mini.pick').builtin.grep_live()
        end,
        desc = 'Find [G]rep',
      },
      {
        '<leader>d',
        function()
          require('mini.extra').pickers.diagnostic()
        end,
        desc = 'Find [D]iagnostics',
      },
      {
        '<leader>e',
        function()
          require('mini.extra').pickers.explorer()
        end,
        desc = 'Find [D]iagnostics',
      },
      {
        '<leader>g',
        function()
          require('mini.extra').pickers.git_hunks()
        end,
        desc = 'Find [D]iagnostics',
      },
      {
        '<leader>s',
        function()
          require('mini.extra').pickers.lsp { scope = 'document_symbol' }
        end,
        desc = 'Find [S]ymbols',
      },
      {
        '<leader>S',
        function()
          require('mini.extra').pickers.lsp { scope = 'workspace_symbol' }
        end,
        desc = 'Find Workspace [S]ymbols',
      },
      {
        '<leader>r',
        function()
          require('mini.extra').pickers.lsp { scope = 'references' }
        end,
        desc = 'Find [R]eferences',
      },
      {
        '<leader>i',
        function()
          require('mini.extra').pickers.lsp { scope = 'implementation' }
        end,
        desc = 'Find [I]mplementation',
      },
      {
        '<leader>T',
        function()
          require('mini.extra').pickers.treesitter()
        end,
        desc = 'Find [T]reesitter nodes',
      },
    },
    after = function()
      local MiniPick = require('mini.pick')
      MiniPick.setup {
        mappings = {
          move_down = '<C-j>',
          move_up = '<C-k>',
        },
        window = {
          prompt_prefix = '   ',
          config = function()
            -- centered on screen
            local height = math.floor(0.618 * vim.o.lines)
            local width = math.floor(0.618 * vim.o.columns)
            return {
              anchor = 'NW',
              border = 'rounded',
              height = height,
              width = width,
              row = math.floor(0.5 * (vim.o.lines - height)),
              col = math.floor(0.5 * (vim.o.columns - width)),
            }
          end,
        },
      }
      vim.ui.select = MiniPick.ui_select
    end,
  },
}
