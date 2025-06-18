require('lz.n').load {
  'nvim-dap-ui',
  keys = {
    {
      '<leader>du',
      function()
        require('dapui').toggle {}
      end,
      desc = 'Dap UI',
    },
  },
  after = function()
    require('dapui').setup {}
  end,
}
