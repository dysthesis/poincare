require('lz.n').load {
  'fidget.nvim',
  after = function()
    require('fidget').setup {}
  end,
}
