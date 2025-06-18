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
          local project_root = vim.fn.getcwd()
          local debug_dir = project_root .. '/target/debug'

          -- Find all potential executables in the debug directory
          local executables = {}
          -- Use pcall to gracefully handle cases where the directory doesn't exist
          local success, dir_iter = pcall(vim.fs.dir, debug_dir)
          if success and dir_iter then
            for file in dir_iter do
              local full_path = debug_dir .. '/' .. file
              -- Check if the file is an executable and not a directory
              if vim.fn.executable(full_path) == 1 then
                table.insert(executables, { path = full_path, name = file })
              end
            end
          end

          -- Case 1: No executables found, fall back to manual input
          if #executables == 0 then
            vim.notify('No debug executables found. Please build your project.', vim.log.levels.WARN)
            return nil
          end

          -- Case 2: Exactly one executable found, use it automatically
          if #executables == 1 then
            vim.notify('Found one executable: ' .. executables[1].name)
            return executables[1].path
          end

          -- Case 3: Multiple executables found, prompt the user
          local display_items = {}
          for _, exec in ipairs(executables) do
            table.insert(display_items, exec.name)
          end

          local res = executables[1].path -- default to the first option
          vim.ui.select(display_items, { prompt = 'Select executable to debug:' }, function(choice)
            if not choice then
              -- User cancelled the selection
              return nil
            end
            -- Find the full path corresponding to the chosen name
            for _, exec in ipairs(executables) do
              if exec.name == choice then
                res = exec.path
              end
            end
          end)

          return res
        end,
        cwd = '${workspaceFolder}',
        stopOnEntry = false,
      },
    }
  end,
}
