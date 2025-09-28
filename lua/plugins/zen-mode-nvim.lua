require('lz.n').load {
  'zen-mode.nvim',
  keys = {
    {
      '<leader>z',
      function()
        require('zen-mode').toggle {}
      end,
      desc = 'Toggle [Z]en',
      mode = 'n',
    },
  },
}
