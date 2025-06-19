require('lz.n').load {
  'neotest',
  keys = {
    {
      '<leader>tr',
      function()
        require('neotest').run.run()
      end,
      desc = '[T]est [R]un nearest',
    },
    {
      '<leader>tf',
      function()
        require('neotest').run.run(vim.api.nvim_buf_get_name(0))
      end,
      desc = '[T]est [F]ile',
    },
    {
      '<leader>tw',
      function()
        require('neotest').watch.toggle(vim.api.nvim_buf_get_name(0))
      end,
      desc = '[T]est [W]atch file',
    },
    {
      '<leader>to',
      function()
        require('neotest').output_panel.toggle()
      end,
      desc = '[T]est [O]utputs',
    },
    {
      '<leader>ts',
      function()
        require('neotest').summary.toggle()
      end,
      desc = '[T]est [S]ummary',
    },
  },
  after = function()
    require('neotest').setup {
      adapters = {
        require('rustaceanvim.neotest'),
      },
      ---@diagnostic disable-next-line: missing-fields
      discovery = {
        enabled = true,
      },
      icons = {
        failed = '',
        passed = '',
        running = '',
        skipped = '',
        unknown = '',
      },
      quickfix = {
        enabled = false,
        open = false,
      },
    }
  end,
}
