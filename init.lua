pcall(function()
  vim.loader.enable()
end)

vim.cmd.filetype('plugin', 'indent', 'on')
vim.cmd.packadd('cfilter') -- Allows filtering the quickfix list with :cfdo

local cmd = vim.cmd
local opt = vim.o

opt.compatible = false
-- Appearance
--- Set theme
vim.g.minimal_transparent = true
vim.g.have_nerd_font = false
cmd.colorscheme('minimal')
opt.conceallevel = 2

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
opt.ignorecase = true
opt.smartindent = true
opt.shiftround = true
opt.softtabstop = 2
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
opt.tabstop = 2
opt.shiftwidth = 2
--- Leader keys
vim.g.mapleader = vim.keycode('<space>')
vim.g.maplocalleader = vim.keycode('<cr>')
--- Clipboard
vim.schedule(function()
  opt.clipboard = 'unnamedplus'
end)

opt.laststatus = 3
opt.termguicolors = true
opt.winborder = 'rounded'
opt.inccommand = 'split'
opt.splitright = true
opt.splitbelow = true
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
  'rust-analyzer',
}

local function enable_lsp(lsp)
  if vim.fn.executable(lsp) == 1 then
    vim.lsp.enable(lsp)
    return true
  end

  return false
end

for _, lsp in ipairs(lsps) do
  enable_lsp(lsp)
end

for _, lsp in ipairs { 'nil', 'nixd' } do
  if enable_lsp(lsp) then
    break
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
  end,
})

-- Tree-sitter
-- vim.api.nvim_create_autocmd('FileType', {
--   callback = function(event)
--     pcall(vim.treesitter.start, event.buf)
--   end,
-- })

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
  {
    'smart-splits.nvim',
    keys = {
      {
        '<A-h>',
        function()
          require('smart-splits').resize_left()
        end,
        desc = 'Resize left',
      },
      {
        '<A-j>',
        function()
          require('smart-splits').resize_down()
        end,
        desc = 'Resize down',
      },
      {
        '<A-k>',
        function()
          require('smart-splits').resize_up()
        end,
        desc = 'Resize up',
      },
      {
        '<A-l>',
        function()
          require('smart-splits').resize_right()
        end,
        desc = 'Resize right',
      },
      {
        '<C-h>',
        function()
          require('smart-splits').move_cursor_left()
        end,
        desc = 'Move cursor left',
      },
      {
        '<C-j>',
        function()
          require('smart-splits').move_cursor_down()
        end,
        desc = 'Move cursor down',
      },
      {
        '<C-k>',
        function()
          require('smart-splits').move_cursor_up()
        end,
        desc = 'Move cursor up',
      },
      {
        '<C-l>',
        function()
          require('smart-splits').move_cursor_right()
        end,
        desc = 'Move cursor right',
      },
      {
        '<C-\\>',
        function()
          require('smart-splits').move_cursor_previous()
        end,
        desc = 'Move cursor to previous split',
      },
    },
    after = function()
      require('smart-splits').setup {}
    end,
  },
  { 'nvim-nio' },
  {
    'nvim-dap',
    keys = {
      {
        '<leader>Db',
        function()
          require('dap').toggle_breakpoint()
        end,
        desc = 'Toggle Breakpoint',
      },

      {
        '<leader>Dc',
        function()
          require('dap').continue()
        end,
        desc = 'Continue',
      },
      {
        '<leader>Ds',
        function()
          require('dap').step_over()
        end,
        desc = 'Step over',
      },
      {
        '<leader>DS',
        function()
          require('dap').step_into()
        end,
        desc = 'Step into',
      },
      {
        '<leader>Dr',
        function()
          require('dap').repl.open()
        end,
        desc = 'Open DAP repl',
      },
      {
        '<leader>DC',
        function()
          require('dap').run_to_cursor()
        end,
        desc = 'Run to Cursor',
      },

      {
        '<leader>DT',
        function()
          require('dap').terminate()
        end,
        desc = 'Terminate',
      },
    },

    load = function(name)
      vim.cmd.packadd('nvim-nio')
      vim.cmd.packadd(name)
      vim.cmd.packadd('nvim-dap-ui')
      vim.cmd.packadd('nvim-dap-virtual-text')
    end,

    after = function()
      vim.fn.sign_define('DapBreakpoint', { text = ' ', texthl = 'DapBreakpoint', linehl = '', numhl = '' })
      vim.fn.sign_define(
        'DapBreakpointCondition',
        { text = ' ', texthl = 'DapBreakpointCondition', linehl = '', numhl = '' }
      )
      vim.fn.sign_define('DapLogPoint', { text = ' ', texthl = 'DapLogPoint', linehl = '', numhl = '' })
      local dap = require('dap')

      dap.adapters.codelldb = {
        type = 'server',
        port = '${port}',
        executable = {
          command = vim.env.CODELLDB_PATH,
          args = { '--port', '${port}' },
        },
      }

      dap.configurations.rust = {
        {
          name = 'Launch',
          type = 'codelldb',
          request = 'launch',
          program = function()
            return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
          end,
          cwd = '${workspaceFolder}',
          stopOnEntry = false,
          args = {},

          -- 💀
          -- if you change `runInTerminal` to true, you might need to change the yama/ptrace_scope setting:
          --
          --    echo 0 | sudo tee /proc/sys/kernel/yama/ptrace_scope
          --
          -- Otherwise you might get the following error:
          --
          --    Error on launch: Failed to attach to the target process
          --
          -- But you should be aware of the implications:
          -- https://www.kernel.org/doc/html/latest/admin-guide/LSM/Yama.html
          -- runInTerminal = false,
        },
      }
      dap.configurations.c = dap.configurations.rust
      dap.configurations.cpp = dap.configurations.rust

      -- Configure nvim-dap-ui to open with nvim-dap
      local ok, dapui = pcall(require, 'dapui')
      if ok then
        dapui.setup {}
        dap.listeners.before.attach.dapui_config = function()
          dapui.open()
        end
        dap.listeners.before.launch.dapui_config = function()
          dapui.open()
        end
        dap.listeners.before.event_terminated.dapui_config = function()
          dapui.close()
        end
        dap.listeners.before.event_exited.dapui_config = function()
          dapui.close()
        end
      else
        vim.notify('nvim-dap-ui failed to load: ' .. tostring(dapui), vim.log.levels.ERROR)
      end

      require('nvim-dap-virtual-text').setup {}
    end,
  },
  {
    'nvim-dap-ui',
    load = function(name)
      -- Ensure core DAP (and its deps) are available before the UI attaches.
      vim.cmd.packadd('nvim-nio')
      vim.cmd.packadd('nvim-dap')
      vim.cmd.packadd(name)
    end,
    keys = {
      {
        '<leader>Do',
        function()
          require('dapui').open()
        end,
        desc = '[D]ebug [O]pen',
      },
      {
        '<leader>Dc',
        function()
          require('dapui').close()
        end,
        desc = '[D]ebug [C]lose',
      },
      {
        '<leader>Dt',
        function()
          require('dapui').toggle()
        end,
        desc = '[D]ebug [T]oggle UI',
      },
    },
    after = function()
      require('dapui').setup()
    end,
  },
  { 'nvim-dap-virtual-text' },
  {
    'nvim-treesitter',
    lazy = false,
    load = function(name)
      local function packadd_if_opt(pkg)
        local paths = vim.fn.globpath(vim.o.packpath, 'pack/*/opt/' .. pkg, true, true)
        if #paths > 0 then
          pcall(vim.cmd.packadd, pkg)
        end
      end

      packadd_if_opt('nvim-treesitter-textobjects')

      -- Ensure parsers/queries shipped as optional plugins are on runtimepath
      -- before the core nvim-treesitter plugin is loaded.
      local function packadd_ts_assets()
        local patterns = {
          'pack/*/opt/nvim-treesitter-grammar-*',
          'pack/*/opt/vimplugin-nvim-treesitter-queries-*',
        }

        for _, pattern in ipairs(patterns) do
          local paths = vim.fn.globpath(vim.o.packpath, pattern, true, true)
          for _, path in ipairs(paths) do
            local name = vim.fn.fnamemodify(path, ':t')
            pcall(vim.cmd.packadd, name)
          end
        end
      end

      packadd_ts_assets()
    end,
    after = function()
      -- New nvim-treesitter rewrite no longer exposes `configs`; use the
      -- top-level setup and wire features ourselves.
      require('nvim-treesitter').setup {}

      -- Enable treesitter highlighting everywhere except LaTeX (upstream queries
      -- are still experimental there).
      vim.api.nvim_create_autocmd('FileType', {
        pattern = '*',
        callback = function(event)
          if event.match == 'latex' then
            return
          end
          pcall(vim.treesitter.start, event.buf, event.match)
        end,
      })

      -- Textobjects configuration + keymaps
      require('nvim-treesitter-textobjects').setup {
        highlight = { enable = true },
        select = {
          lookahead = true,
          selection_modes = {
            ['@block.outer'] = '<c-v>',
            ['@frame.outer'] = '<c-v>',
            ['@statement.outer'] = 'V',
            ['@assignment.outer'] = 'V',
            ['@comment.outer'] = 'V',
            ['@comment.inner'] = 'v',
            ['@conditional.inner'] = 'v',
          },
        },
        move = {
          set_jumps = true,
        },
      }

      local select = require('nvim-treesitter-textobjects.select')
      local move = require('nvim-treesitter-textobjects.move')
      local swap = require('nvim-treesitter-textobjects.swap')

      local function map_sel(lhs, capture, desc)
        vim.keymap.set({ 'x', 'o' }, lhs, function()
          select.select_textobject(capture, 'textobjects')
        end, { desc = desc })
      end

      map_sel('af', '@function.outer', 'TS select function outer')
      map_sel('if', '@function.inner', 'TS select function inner')
      map_sel('ac', '@class.outer', 'TS select class outer')
      map_sel('ic', '@class.inner', 'TS select class inner')
      map_sel('aC', '@call.outer', 'TS select call outer')
      map_sel('iC', '@call.inner', 'TS select call inner')
      map_sel('a#', '@comment.outer', 'TS select comment outer')
      map_sel('i#', '@comment.inner', 'TS select comment inner')
      map_sel('ai', '@conditional.outer', 'TS select conditional outer')
      map_sel('ii', '@conditional.outer', 'TS select conditional outer')
      map_sel('al', '@loop.outer', 'TS select loop outer')
      map_sel('il', '@loop.inner', 'TS select loop inner')
      map_sel('aP', '@parameter.outer', 'TS select parameter outer')
      map_sel('iP', '@parameter.inner', 'TS select parameter inner')
      map_sel('aa', '@assignment.outer', 'TS select assignment outer')
      map_sel('ia', '@assignment.inner', 'TS select assignment inner')
      map_sel('aL', '@assignment.lhs', 'TS select assignment lhs')
      map_sel('iL', '@assignment.lhs', 'TS select assignment lhs')
      map_sel('aR', '@assignment.rhs', 'TS select assignment rhs')
      map_sel('iR', '@assignment.rhs', 'TS select assignment rhs')
      map_sel('aA', '@attribute.outer', 'TS select attribute outer')
      map_sel('iA', '@attribute.inner', 'TS select attribute inner')
      map_sel('ab', '@block.outer', 'TS select block outer')
      map_sel('ib', '@block.inner', 'TS select block inner')
      map_sel('aF', '@frame.outer', 'TS select frame outer')
      map_sel('iF', '@frame.inner', 'TS select frame inner')
      map_sel('an', '@number.outer', 'TS select number')
      map_sel('in', '@number.inner', 'TS select number')
      map_sel('aX', '@regex.outer', 'TS select regex outer')
      map_sel('iX', '@regex.inner', 'TS select regex inner')
      map_sel('ar', '@return.outer', 'TS select return outer')
      map_sel('ir', '@return.inner', 'TS select return inner')
      map_sel('as', '@statement.outer', 'TS select statement')
      map_sel('ns', '@scopename.inner', 'TS select scope name')

      vim.keymap.set('n', '<leader>a', function()
        swap.swap_next('@parameter.inner', 'textobjects', true)
      end, { desc = 'TS swap parameter with next' })
      vim.keymap.set('n', '<leader>A', function()
        swap.swap_previous('@parameter.inner', 'textobjects', true)
      end, { desc = 'TS swap parameter with previous' })

      vim.keymap.set({ 'n', 'x', 'o' }, ']m', function()
        move.goto_next_start('@function.outer', 'textobjects')
      end, { desc = 'TS next function start' })
      vim.keymap.set({ 'n', 'x', 'o' }, ']P', function()
        move.goto_next_start('@parameter.outer', 'textobjects')
      end, { desc = 'TS next parameter start' })
      vim.keymap.set({ 'n', 'x', 'o' }, ']M', function()
        move.goto_next_end('@function.outer', 'textobjects')
      end, { desc = 'TS next function end' })
      vim.keymap.set({ 'n', 'x', 'o' }, ']p', function()
        move.goto_next_end('@parameter.outer', 'textobjects')
      end, { desc = 'TS next parameter end' })

      vim.keymap.set({ 'n', 'x', 'o' }, '[m', function()
        move.goto_previous_start('@function.outer', 'textobjects')
      end, { desc = 'TS prev function start' })
      vim.keymap.set({ 'n', 'x', 'o' }, '[P', function()
        move.goto_previous_start('@parameter.outer', 'textobjects')
      end, { desc = 'TS prev parameter start' })
      vim.keymap.set({ 'n', 'x', 'o' }, '[M', function()
        move.goto_previous_end('@function.outer', 'textobjects')
      end, { desc = 'TS prev function end' })
      vim.keymap.set({ 'n', 'x', 'o' }, '[p', function()
        move.goto_previous_end('@parameter.outer', 'textobjects')
      end, { desc = 'TS prev parameter end' })
    end,
  },
  {
    'mini.surround',
    event = 'BufReadPost',
    after = function()
      require('mini.surround').setup {}
    end,
  },
  {
    'ultimate-autopair.nvim',
    event = { 'InsertEnter', 'CmdlineEnter' },
    after = function()
      require('ultimate-autopair').setup {}
    end,
  },
  {
    'conform.nvim',
    event = 'BufWritePre',
    after = function()
      require('conform').setup {
        notify_on_error = false,
        format_on_save = function(bufnr)
          -- Disable "format_on_save lsp_fallback" for languages that don't
          -- have a well standardized coding style. You can add additional
          -- languages here or re-enable it for the disabled ones.
          local disable_filetypes = {}
          return {
            timeout_ms = 500,
            lsp_fallback = not disable_filetypes[vim.bo[bufnr].filetype],
          }
        end,
        format_after_save = {
          async = true,
        },
        formatters_by_ft = {
          lua = { 'stylua' },
          markdown = { 'markdownlint' },
          nix = { 'alejandra' },
          c = { 'clang-format' },
          rust = { 'rustfmt' },
          go = { 'go/fmt' },
        },
      }
    end,
  },
  {
    'nvim-lint',
    event = { 'BufReadPre', 'BufNewFile' },
    after = function()
      local lint = require('lint')
      lint.linters.zlint = {
        cmd = 'zlint',
        stdin = false,
        append_fname = false,
        args = { '-f', 'gh' },
        stream = 'both',
        ignore_exitcode = true,
        parser = function(output, bufnr)
          local items = {}
          -- get buffer by file name
          for line in vim.gsplit(output, '\n') do
            local level, file, row, col, message = line:match('::(%w+)%sfile=([^,]+),line=(%d+),col=(%d+),title=(.*)')
            local severity = nil
            -- map linter levels to diagnostic levels
            -- zlint levels: error, warning, off
            if level == 'error' then
              severity = vim.diagnostic.severity.ERROR
            elseif level == 'warning' then
              severity = vim.diagnostic.severity.WARN
            end

            if file and severity then
              local l_bufnr = vim.fn.bufnr(file)
              if l_bufnr > -1 and l_bufnr == bufnr then
                table.insert(items, {
                  lnum = tonumber(row) - 1,
                  col = tonumber(col) - 1,
                  message = message,
                  source = 'zlint',
                  bufnr = bufnr,
                  severity = severity,
                })
              end
            end
          end

          return items
        end,
      }
      lint.linters_by_ft = {
        zig = { 'zlint' },
        rust = { 'clippy' },
        nix = { 'statix' },
        lua = { 'selene' },
      }
      local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
        group = lint_augroup,
        callback = function()
          -- Only run the linter in buffers that you can modify in order to
          -- avoid superfluous noise, notably within the handy LSP pop-ups that
          -- describe the hovered symbol using Markdown.
          if vim.opt_local.modifiable:get() then
            lint.try_lint()
          end
        end,
      })
    end,
  },
  {
    'lean.nvim',
    event = { 'BufReadPre *.lean', 'BufNewFile *.lean' },
    load = function(name)
      vim.cmd.packadd('plenary.nvim')
      vim.cmd.packadd(name)
    end,

    after = function()
      require('lean').setup {
        mappings = true,
      }
    end,
  },
  {
    'blink.cmp',
    event = 'InsertEnter',
    load = function(name)
      vim.cmd.packadd('mini.icons')
      vim.cmd.packadd(name)
    end,
    after = function()
      local cmp = require('blink.cmp')
      cmp.setup {
        completion = {
          accept = {
            -- experimental auto-brackets support
            auto_brackets = {
              enabled = true,
            },
          },
          documentation = { auto_show = true, auto_show_delay_ms = 0, window = { border = 'single' } },
          ghost_text = { enabled = true },
          menu = {
            border = 'rounded',
            -- Use mini.icons
            draw = {
              treesitter = { 'lsp' },
              gap = 2,
              components = {
                kind_icon = {
                  ellipsis = false,
                  text = function(ctx)
                    local kind_icon, _, _ = require('mini.icons').get('lsp', ctx.kind)
                    return kind_icon
                  end,
                  -- Optionally, you may also use the highlights from mini.icons
                  highlight = function(ctx)
                    local _, hl, _ = require('mini.icons').get('lsp', ctx.kind)
                    return hl
                  end,
                },
              },
            },
          },
        },

        fuzzy = {
          implementation = 'rust',
        },
        appearance = { use_nvim_cmp_as_default = false },
        cmdline = { completion = { ghost_text = { enabled = false } } },

        signature = { enabled = true },
        -- Pick sources depending on file type and/or tree-sitter node
        sources = {
          default = function()
            local success, node = pcall(vim.treesitter.get_node)
            if vim.bo.filetype == 'lua' then
              return { 'lsp', 'path' }
            elseif
              success
              and node
              and vim.tbl_contains({ 'comment', 'line_comment', 'block_comment' }, node:type())
            then
              return { 'buffer' }
            else
              return { 'lsp', 'path', 'snippets', 'buffer' }
            end
          end,
        },
      }
    end,
  },
}
