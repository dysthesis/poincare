require('lz.n').load {
  'echasnovski/mini.indentscope',
  event = 'BufReadPost',
  after = function()
    require('mini.indentscope').setup()
  end,
}
