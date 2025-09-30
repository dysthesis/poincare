require('lz.n').load {
  'lean.nvim',
  event = { 'BufReadPre *.lean', 'BufNewFile *.lean' },
  after = function()
    require('lean').setup { mappings = true }
  end,
}
