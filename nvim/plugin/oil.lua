require('lz.n').load {
  'oil.nvim',
  keys = {
    { '-', '<CMD>Oil<CR>', desc = 'Open parent directory (Oil)' },
  },
  after = function()
    require('oil').setup {}
  end,
}
