require('lz.n').load {
  'lspsaga.nvim',
  after = function()
    require('lspsaga').setup()
  end,
}
