require('lz.n').load {
  'mini.surround',
  event = 'BufReadPost',
  after = function()
    require('mini.surround').setup {}
  end,
}
