require('lz.n').load {
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
        -- Change this to your path!
        command = vim.g.codelldb_path,
        args = { '--port', '${port}' },
      },
    }

    -- dap.configurations.rust = {
    --   {
    --     name = 'Launch file',
    --     type = 'codelldb',
    --     request = 'launch',
    --     program = function()
    --       local project_root = vim.fn.getcwd()
    --       local debug_dir = project_root .. '/target/debug'
    --
    --       -- Find all potential executables in the debug directory
    --       local executables = {}
    --       -- Use pcall to gracefully handle cases where the directory doesn't exist
    --       local success, dir_iter = pcall(vim.fs.dir, debug_dir)
    --       if success and dir_iter then
    --         for file in dir_iter do
    --           local full_path = debug_dir .. '/' .. file
    --           -- Check if the file is an executable and not a directory
    --           if vim.fn.executable(full_path) == 1 then
    --             table.insert(executables, { path = full_path, name = file })
    --           end
    --         end
    --       end
    --
    --       -- Case 1: No executables found, fall back to manual input
    --       if #executables == 0 then
    --         vim.notify('No debug executables found. Please build your project.', vim.log.levels.WARN)
    --         return nil
    --       end
    --
    --       -- Case 2: Exactly one executable found, use it automatically
    --       if #executables == 1 then
    --         vim.notify('Found one executable: ' .. executables[1].name)
    --         return executables[1].path
    --       end
    --
    --       -- Case 3: Multiple executables found, prompt the user
    --       local display_items = {}
    --       for _, exec in ipairs(executables) do
    --         table.insert(display_items, exec.name)
    --       end
    --
    --       local res = executables[1].path -- default to the first option
    --       vim.ui.select(display_items, { prompt = 'Select executable to debug:' }, function(choice)
    --         if not choice then
    --           -- User cancelled the selection
    --           return nil
    --         end
    --         -- Find the full path corresponding to the chosen name
    --         for _, exec in ipairs(executables) do
    --           if exec.name == choice then
    --             res = exec.path
    --           end
    --         end
    --       end)
    --
    --       return res
    --     end,
    --     cwd = '${workspaceFolder}',
    --     stopOnEntry = false,
    --   },
    -- }

    dap.configurations.zig = {
      {
        name = 'Launch file',
        type = 'codelldb',
        request = 'launch',
        program = function()
          local root = vim.fn.getcwd()

          local execs = vim.fn.glob(root .. '/zig-out/bin/*', false, true)
          local test_execs = vim.fn.glob(root .. '/zig-cache/o/*/test', false, true)

          local all_paths = {}

          vim.list_extend(all_paths, execs)
          vim.list_extend(all_paths, test_execs)

          local for_display = { 'Select executable:' }

          for index, value in ipairs(all_paths) do
            table.insert(for_display, string.format('%d. %s', index, value))
          end

          local choice = vim.fn.inputlist(for_display)
          local final_choice = all_paths[choice]

          return final_choice
        end,
        cwd = '${workspaceFolder}',
        stopOnEntry = false,
      },
    }
    local dapui = require('dapui')
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
  end,

  require('nvim-dap-virtual-text').setup {},
}
