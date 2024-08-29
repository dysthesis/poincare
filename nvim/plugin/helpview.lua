require('lz.n').load {
  'helpview.nvim',
  ft = 'help',
  after = function()
    require('helpview').setup()
  end,
}
