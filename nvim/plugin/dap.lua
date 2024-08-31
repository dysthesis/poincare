require('lz.n').load {
  'nvim-dap',

  keys = {
    {
      '<leader>db',
      function()
        require('dap').toggle_breakpoint()
      end,
      desc = '[D]ebug [B]reakpoint',
    },
    {
      '<leader>ds',
      function()
        require('dap').continue()
      end,
      desc = '[D]ebug [S]tart',
    },
    {
      '<leader>dt',
      function()
        require('dapui').toggle()
      end,
      desc = '[D]ebug [T]oggle UI',
    },
  },

  load = function(name)
    vim.cmd.packadd(name)
    vim.cmd.packadd('nvim-dap-ui')
  end,

  after = function()
    local dap = require('dap')
    local dap_ui = require('dapui')

    require('nvim-dap-virtual-text').setup {}
    dap_ui.setup {}

    dap.listeners.before.attach.dapui_config = function()
      dap_ui.open()
    end

    dap.listeners.before.launch.dapui_config = function()
      dap_ui.open()
    end

    dap.listeners.before.event_exited.dapui_config = function()
      dap_ui.close()
    end

    dap.listeners.before.event_terminated.dapui_config = function()
      dap_ui.close()
    end
  end,
}
