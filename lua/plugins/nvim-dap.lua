require('lz.n').load {
  'nvim-dap',
  keys = {
    {
      '<leader>db',
      function()
        require('dap').toggle_breakpoint()
      end,
      desc = 'Toggle Breakpoint',
    },

    {
      '<leader>dc',
      function()
        require('dap').continue()
      end,
      desc = 'Continue',
    },

    {
      '<leader>dC',
      function()
        require('dap').run_to_cursor()
      end,
      desc = 'Run to Cursor',
    },

    {
      '<leader>dT',
      function()
        require('dap').terminate()
      end,
      desc = 'Terminate',
    },
  },

  after = function()
    local dap = require('dap')

    dap.adapters.codelldb = {
      type = 'server',
      port = '${port}',
      executable = {
        -- Change this to your path!
        command = vim.g.codelldb_path,
        args = { '--port', '${port}' },
      },
    }

    dap.configurations.rust = {
      {
        name = 'Launch file',
        type = 'codelldb',
        request = 'launch',
        program = function()
          return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
        end,
        cwd = '${workspaceFolder}',
        stopOnEntry = false,
      },
    }

    require('dapui').setup {}
  end,
}
