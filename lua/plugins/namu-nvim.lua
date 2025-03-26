require('lz.n').load {
  'namu.nvim',
  keys = {
    { '<leader>ss', '<cmd>Namu symbols<cr>', desc = '[S]earch [S]ymbols' },
  },
  after = function()
    require('namu').setup {}
  end,
}
