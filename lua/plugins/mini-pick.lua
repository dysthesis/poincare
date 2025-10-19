require('lz.n').load {
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
      options = {
        use_cache = true,
      },
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
}
