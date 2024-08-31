require('lz.n').load {
  'neotest',
  keys = {
    {
      '<leader>Ta',
      function()
        require('neotest').run.run { suite = true }
      end,
      desc = '[T]est [A]ll',
    },
    {
      '<leader>Td',
      function()
        require('neotest').run.run { strategy = 'dap' }
      end,
      desc = '[T]est [D]ebug nearest',
    },
    {
      '<leader>Tf',
      function()
        require('neotest').run.run(vim.fn.expand('%'))
      end,
      desc = '[T]est run [F]ile',
    },
    {
      '<leader>Tj',
      function()
        require('neotest').jump.prev { status = 'failed' }
      end,
      desc = 'Jump to previous failed test',
    },
    {
      '<leader>Tk',
      function()
        require('neotest').jump.next { status = 'failed' }
      end,
      desc = 'Jump to next failed test',
    },
    {
      '<leader>To',
      function()
        require('neotest').output.open { enter = true }
      end,
      desc = '[T]est [O]utput of nearest test',
    },
    {
      '<leader>Tp',
      function()
        require('neotest').output_panel.toggle()
      end,
      desc = '[T]est open raw output [P]anel',
    },
    {
      '<leader>Tr',
      function()
        require('neotest').run.run()
      end,
      desc = '[T]est [R]un nearest',
    },
    {
      '<leader>Ts',
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
    }
  end,
}
