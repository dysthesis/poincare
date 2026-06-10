pcall(vim.loader.enable)

local api, cmd, opt = vim.api, vim.cmd, vim.o
local autocmd, augroup = api.nvim_create_autocmd, api.nvim_create_augroup

cmd.filetype('plugin', 'indent', 'on')
cmd.packadd('cfilter') -- :Cfilter and :Lfilter

-- Appearance
vim.g.minimal_transparent = true
-- minimal.nvim lives in pack/*/opt; :colorscheme would find it there anyway,
-- but only packadd puts its after/queries/* on the runtimepath. Deliberately
-- eager: deferring the colourscheme causes a flash of unstyled UI.
cmd.packadd('minimal.nvim')
cmd.colorscheme('minimal')
opt.conceallevel = 2

vim.wo.relativenumber = true
opt.colorcolumn = '80'

-- Statusline
cmd('hi StatusMode gui=bold cterm=bold')
local mode_abbr = {
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
}
vim.mode_abbr = function()
  local mode = api.nvim_get_mode().mode
  return mode_abbr[mode] or mode:upper()
end
opt.statusline = '%#StatusMode#%{v:lua.vim.mode_abbr()}%* %t %=%y 0x%B %l:%c %p%%'

-- Command-line completion UI
opt.wildmenu = true
opt.wildmode = 'noselect' -- command-line completion behaviour
opt.wildoptions = 'pum,fuzzy' -- show popup menu with fuzzy matching
opt.completeopt = 'menu,menuone,popup,fuzzy,noselect' -- modern completion menu
-- Incrementally refresh wildmenu as you type on :, /, ?
autocmd('CmdlineChanged', {
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

-- I make these typo way too much
for from, to in pairs {
  ['W!'] = 'w!',
  ['Q!'] = 'q!',
  ['Qall!'] = 'qall!',
  ['Wq'] = 'wq',
  ['Wa'] = 'wa',
  ['wQ'] = 'wq',
  ['WQ'] = 'wq',
  ['W'] = 'w',
  ['Q'] = 'q',
} do
  api.nvim_command('cnoreabbrev ' .. from .. ' ' .. to)
end

-- Persist view
local view_group = augroup('auto_view', { clear = true })
autocmd({ 'BufWinLeave', 'BufWritePost', 'WinLeave' }, {
  desc = 'Save view with mkview for real files',
  group = view_group,
  callback = function(args)
    if vim.b[args.buf].view_activated then
      cmd.mkview { mods = { emsg_silent = true } }
    end
  end,
})
autocmd('BufWinEnter', {
  desc = 'Try to load file view if available and enable view saving for real files',
  group = view_group,
  callback = function(args)
    local b = vim.b[args.buf]
    if b.view_activated then
      return
    end

    local bo = vim.bo[args.buf]
    local filetype = bo.filetype
    if
      bo.buftype == ''
      and filetype ~= ''
      and filetype ~= 'gitcommit'
      and filetype ~= 'gitrebase'
      and filetype ~= 'svg'
      and filetype ~= 'hgcommit'
    then
      b.view_activated = true
      cmd.loadview { mods = { emsg_silent = true } }
    end
  end,
})
opt.tabstop = 2
opt.shiftwidth = 2
vim.g.mapleader = ' '
vim.g.maplocalleader = '\r'
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

-- LSP
local diagnostic_severity = vim.diagnostic.severity
vim.diagnostic.config {
  virtual_text = {
    format = function(diagnostic)
      -- diagnostic.source is a name string, not a client id.
      return (diagnostic.source and (diagnostic.source .. ': ') or '') .. diagnostic.message
    end,
  },

  underline = true,
  signs = {
    text = {
      [diagnostic_severity.ERROR] = '󰅚 ',
      [diagnostic_severity.WARN] = '󰀪 ',
      [diagnostic_severity.INFO] = '󰋽 ',
      [diagnostic_severity.HINT] = '󰌶 ',
    },
    numhl = {
      [diagnostic_severity.ERROR] = 'ErrorMsg',
      [diagnostic_severity.WARN] = 'WarningMsg',
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

local function enable_lsp(lsp)
  -- A config's name and executable can differ (for example, basedpyright).
  local cfg = vim.lsp.config[lsp]
  local bin = cfg and type(cfg.cmd) == 'table' and cfg.cmd[1] or lsp
  if vim.fn.executable(bin) == 1 then
    vim.lsp.enable(lsp)
  end
end

for _, lsp in ipairs {
  'lua-language-server',
  'rust-analyzer',
  'clangd',
  'nil',
  'basedpyright',
  'ty',
} do
  enable_lsp(lsp)
end

if not vim.lsp.is_enabled('nil') then
  enable_lsp('nixd')
end

autocmd('LspAttach', {
  desc = 'LSP actions',
  callback = function(event)
    local bufnr = event.buf
    vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })

    local map = vim.keymap.set
    local opts = { buf = bufnr }

    map('n', 'K', function()
      vim.lsp.buf.hover { focusable = true }
    end, opts)

    map('n', 'gd', vim.lsp.buf.definition, opts)
    map({ 'n', 'x' }, 'gq', '<cmd>lua vim.lsp.buf.format({async = true})<cr>', opts)
    map('i', '<C-s>', vim.lsp.buf.signature_help, opts)
    map('n', '<leader>cd', vim.lsp.buf.declaration, opts)
    map('n', '<leader>ci', vim.lsp.buf.implementation, opts)
    map('n', '<leader>ct', vim.lsp.buf.type_definition, opts)
    map('n', '<leader>cR', vim.lsp.buf.references, opts)
    map('n', '<leader>ca', vim.lsp.buf.code_action, opts)
    map('n', '<leader>cr', vim.lsp.buf.rename, opts)

    -- Toggle inlay hints such as rust-analyzer's implicit `drop(...)` markers.
    map('n', '<leader>ch', function()
      vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = bufnr }, { bufnr = bufnr })
    end, { buf = bufnr, desc = 'Toggle inlay hints' })
  end,
})

-- Tree-sitter highlighting is started by the FileType autocmd registered in
-- nvim-treesitter's after() hook below, which carries the latex exclusion.

-- Plugins
local function call(module, method, namespace)
  return function()
    local target = require(module)
    target = namespace and target[namespace] or target
    target[method]()
  end
end

local function lsp_picker(scope)
  return function()
    require('mini.extra').pickers.lsp { scope = scope }
  end
end

-- Picker
require('lz.n').load {
  {
    'mini.pick',
    cmd = 'Pick',
    load = function(name)
      cmd.packadd(name)
      cmd.packadd('mini.extra')
    end,
    keys = {
      { '<leader>f', call('mini.pick', 'files', 'builtin'), desc = 'Find [F]iles' },
      { '<leader>/', call('mini.pick', 'grep_live', 'builtin'), desc = 'Find [G]rep' },
      { '<leader>d', call('mini.extra', 'diagnostic', 'pickers'), desc = 'Find [D]iagnostics' },
      { '<leader>e', call('mini.extra', 'explorer', 'pickers'), desc = 'File [E]xplorer' },
      { '<leader>g', call('mini.extra', 'git_hunks', 'pickers'), desc = 'Find [G]it hunks' },
      { '<leader>s', lsp_picker('document_symbol'), desc = 'Find [S]ymbols' },
      { '<leader>S', lsp_picker('workspace_symbol'), desc = 'Find Workspace [S]ymbols' },
      { '<leader>r', lsp_picker('references'), desc = 'Find [R]eferences' },
      { '<leader>i', lsp_picker('implementation'), desc = 'Find [I]mplementation' },
      { '<leader>T', call('mini.extra', 'treesitter', 'pickers'), desc = 'Find [T]reesitter nodes' },
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
            local floor, lines, columns = math.floor, vim.o.lines, vim.o.columns
            local height, width = floor(0.618 * lines), floor(0.618 * columns)
            return {
              anchor = 'NW',
              border = 'rounded',
              height = height,
              width = width,
              row = floor(0.5 * (lines - height)),
              col = floor(0.5 * (columns - width)),
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
      { '<A-h>', call('smart-splits', 'resize_left'), desc = 'Resize left' },
      { '<A-j>', call('smart-splits', 'resize_down'), desc = 'Resize down' },
      { '<A-k>', call('smart-splits', 'resize_up'), desc = 'Resize up' },
      { '<A-l>', call('smart-splits', 'resize_right'), desc = 'Resize right' },
      { '<C-h>', call('smart-splits', 'move_cursor_left'), desc = 'Move cursor left' },
      { '<C-j>', call('smart-splits', 'move_cursor_down'), desc = 'Move cursor down' },
      { '<C-k>', call('smart-splits', 'move_cursor_up'), desc = 'Move cursor up' },
      { '<C-l>', call('smart-splits', 'move_cursor_right'), desc = 'Move cursor right' },
      { '<C-\\>', call('smart-splits', 'move_cursor_previous'), desc = 'Move cursor to previous split' },
    },
  },
  {
    'nvim-dap',
    keys = {
      { '<leader>Db', call('dap', 'toggle_breakpoint'), desc = 'Toggle Breakpoint' },
      { '<leader>Dc', call('dap', 'continue'), desc = 'Continue' },
      { '<leader>Ds', call('dap', 'step_over'), desc = 'Step over' },
      { '<leader>DS', call('dap', 'step_into'), desc = 'Step into' },
      { '<leader>Dr', call('dap', 'open', 'repl'), desc = 'Open DAP repl' },
      { '<leader>DC', call('dap', 'run_to_cursor'), desc = 'Run to Cursor' },
      { '<leader>DT', call('dap', 'terminate'), desc = 'Terminate' },
    },

    load = function(name)
      cmd.packadd('nvim-nio')
      cmd.packadd(name)
      cmd.packadd('nvim-dap-ui')
      cmd.packadd('nvim-dap-virtual-text')
    end,

    after = function()
      vim.fn.sign_define('DapBreakpoint', { text = ' ', texthl = 'DapBreakpoint', linehl = '', numhl = '' })
      vim.fn.sign_define(
        'DapBreakpointCondition',
        { text = ' ', texthl = 'DapBreakpointCondition', linehl = '', numhl = '' }
      )
      vim.fn.sign_define('DapLogPoint', { text = ' ', texthl = 'DapLogPoint', linehl = '', numhl = '' })
      local dap = require('dap')

      -- Function adapter: codelldb comes from the project env (README
      -- policy), so resolve and validate it at session start, not at boot.
      dap.adapters.codelldb = function(cb)
        local command = vim.env.CODELLDB_PATH or 'codelldb'
        if vim.fn.executable(command) ~= 1 then
          vim.notify(
            'codelldb not found. Add it to the project env, e.g.\n'
              .. '  nix shell "nixpkgs#vscode-extensions.vadimcn.vscode-lldb.adapter"\n'
              .. 'or point $CODELLDB_PATH at the binary\n'
              .. '  (${vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb/adapter/codelldb).',
            vim.log.levels.ERROR
          )
          return
        end
        cb {
          type = 'server',
          port = '${port}',
          executable = { command = command, args = { '--port', '${port}' } },
        }
      end

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
          -- runInTerminal=true may require lowering Linux's Yama ptrace_scope.
        },
      }
      dap.configurations.c = dap.configurations.rust
      dap.configurations.cpp = dap.configurations.rust

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
    load = function()
      -- Load core DAP through lz.n so its before/after hooks run (adapter and
      -- listener setup); nvim-dap's load function also adds the UI package.
      require('lz.n').trigger_load('nvim-dap')
    end,
    keys = {
      { '<leader>Do', call('dapui', 'open'), desc = '[D]ebug [O]pen' },
      { '<leader>Dx', call('dapui', 'close'), desc = '[D]ebug Close UI' },
      { '<leader>Dt', call('dapui', 'toggle'), desc = '[D]ebug [T]oggle UI' },
    },
    -- No after() here: nvim-dap's after() (reached via trigger_load above)
    -- already runs dapui.setup and wires the listeners; a second setup()
    -- deletes and recreates every element buffer.
  },
  {
    'nvim-treesitter',
    lazy = false,
    load = function()
      cmd.packadd('nvim-treesitter-textobjects')
    end,
    after = function()
      -- Enable treesitter highlighting everywhere except LaTeX (upstream queries
      -- are still experimental there).
      autocmd('FileType', {
        callback = function(event)
          if event.match ~= 'latex' then
            pcall(vim.treesitter.start, event.buf, event.match)
          end
        end,
      })

      -- Textobjects configuration + keymaps
      require('nvim-treesitter-textobjects').setup {
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
      local map = vim.keymap.set

      local function map_sel(lhs, capture, desc)
        map({ 'x', 'o' }, lhs, function()
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

      map('n', '<leader>a', function()
        swap.swap_next('@parameter.inner', 'textobjects')
      end, { desc = 'TS swap parameter with next' })
      map('n', '<leader>A', function()
        swap.swap_previous('@parameter.inner', 'textobjects')
      end, { desc = 'TS swap parameter with previous' })

      local function map_move(lhs, method, capture, desc)
        map({ 'n', 'x', 'o' }, lhs, function()
          move[method](capture, 'textobjects')
        end, { desc = desc })
      end

      map_move(']m', 'goto_next_start', '@function.outer', 'TS next function start')
      map_move(']P', 'goto_next_start', '@parameter.outer', 'TS next parameter start')
      map_move(']M', 'goto_next_end', '@function.outer', 'TS next function end')
      map_move(']p', 'goto_next_end', '@parameter.outer', 'TS next parameter end')
      map_move('[m', 'goto_previous_start', '@function.outer', 'TS prev function start')
      map_move('[P', 'goto_previous_start', '@parameter.outer', 'TS prev parameter start')
      map_move('[M', 'goto_previous_end', '@function.outer', 'TS prev function end')
      map_move('[p', 'goto_previous_end', '@parameter.outer', 'TS prev parameter end')
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
        format_after_save = { timeout_ms = 500, lsp_format = 'fallback' },
        formatters_by_ft = {
          lua = { 'stylua' },
          markdown = { 'markdownlint' },
          nix = { 'alejandra' },
          c = { 'clang-format' },
          rust = { 'rustfmt' },
          go = { 'gofmt' },
          python = { 'black' },
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
          for line in vim.gsplit(output, '\n') do
            local level, file, row, col, message = line:match('::(%w+)%sfile=([^,]+),line=(%d+),col=(%d+),title=(.*)')
            local severity
            if level == 'error' then
              severity = diagnostic_severity.ERROR
            elseif level == 'warning' then
              severity = diagnostic_severity.WARN
            end

            if severity then
              local l_bufnr = vim.fn.bufnr(file)
              if l_bufnr > -1 and l_bufnr == bufnr then
                items[#items + 1] = {
                  lnum = tonumber(row) - 1,
                  col = tonumber(col) - 1,
                  message = message,
                  source = 'zlint',
                  bufnr = bufnr,
                  severity = severity,
                }
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
      autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
        group = augroup('lint', { clear = true }),
        callback = function()
          -- Only run the linter in buffers that you can modify in order to
          -- avoid superfluous noise, notably within the handy LSP pop-ups that
          -- describe the hovered symbol using Markdown.
          if vim.bo.modifiable then
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
      cmd.packadd('plenary.nvim')
      cmd.packadd(name)
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
      cmd.packadd('mini.icons')
      cmd.packadd(name)
    end,
    after = function()
      local cmp = require('blink.cmp')
      local function clangd_score(a, b)
        -- blink copies clangd's extension score to lsp_score, then uses
        -- score for fuzzy ranking; clangd recommends multiplying them.
        if a.lsp_score == nil or b.lsp_score == nil or a.score == nil or b.score == nil then
          return nil
        end

        local a_score = a.lsp_score * a.score
        local b_score = b.lsp_score * b.score
        if a_score == b_score then
          return nil
        end

        return a_score > b_score
      end

      cmp.setup {
        completion = {
          accept = {
            auto_brackets = {
              enabled = true,
            },
          },
          documentation = { auto_show = true, auto_show_delay_ms = 0, window = { border = 'single' } },
          ghost_text = { enabled = true },
          menu = {
            border = 'rounded',
            draw = {
              treesitter = { 'lsp' },
              gap = 2,
              components = {
                kind_icon = {
                  ellipsis = false,
                  text = function(ctx)
                    local kind_icon = require('mini.icons').get('lsp', ctx.kind)
                    return kind_icon
                  end,
                  highlight = function(ctx)
                    local _, hl = require('mini.icons').get('lsp', ctx.kind)
                    return hl
                  end,
                },
              },
            },
          },
        },

        fuzzy = {
          implementation = 'rust',
          sorts = function()
            if #vim.lsp.get_clients { bufnr = 0, name = 'clangd' } > 0 then
              return { clangd_score, 'score', 'sort_text' }
            end

            return { 'score', 'sort_text' }
          end,
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
            end

            local node_type = success and node and node:type()
            if node_type == 'comment' or node_type == 'line_comment' or node_type == 'block_comment' then
              return { 'buffer' }
            end

            return { 'lsp', 'path', 'snippets', 'buffer' }
          end,
        },
      }
    end,
  },
  {
    'gitsigns.nvim',
    event = 'BufReadPost',
    after = function()
      require('gitsigns').setup {
        signs = {
          add = { text = '│' },
          change = { text = '│' },
          delete = { text = '󰍵' },
          topdelete = { text = '‾' },
          changedelete = { text = '~' },
          untracked = { text = '┆' },
        },

        current_line_blame = true,

        on_attach = function(bufnr)
          local gs = package.loaded.gitsigns

          local function opts(desc)
            return { buf = bufnr, desc = desc }
          end

          local map = vim.keymap.set

          map('n', '<leader>hr', gs.reset_hunk, opts('Reset Hunk'))
          map('n', '<leader>hp', gs.preview_hunk, opts('Preview Hunk'))
          map('n', '<leader>b', gs.blame_line, opts('Blame Line'))
        end,
      }
    end,
  },
  {
    'clangd_extensions.nvim',
    ft = { 'c', 'h', 'cpp', 'hpp' },
    -- Note: avoid <leader>ch / <leader>ct here — the LspAttach autocmd maps
    -- those buffer-locally (inlay hints / type definition) in every LSP
    -- buffer, which would shadow these global triggers.
    keys = {
      { '<leader>cs', '<cmd>ClangdSwitchSourceHeader<cr>', desc = 'Switch [S]ource/Header' },
      { '<leader>cT', '<cmd>ClangdAST<cr>', desc = 'View Abstract Syntax [T]ree' },
    },
    after = function()
      require('clangd_extensions').setup {
        ast = {
          role_icons = {
            type = '',
            declaration = '',
            expression = '',
            specifier = '',
            statement = '',
            ['template argument'] = '',
          },

          kind_icons = {
            Compound = '',
            Recovery = '',
            TranslationUnit = '',
            PackExpansion = '',
            TemplateTypeParm = '',
            TemplateTemplateParm = '',
            TemplateParamObject = '',
          },

          highlights = { detail = 'Comment' },
        },
        memory_usage = { border = 'none' },
        symbol_info = { border = 'none' },
      }
    end,
  },
}
