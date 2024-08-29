require('lz.n').load {
  'trouble.nvim',
  cmd = 'Trouble',
  keys = {
    { '<leader>xx', '<CMD>Trouble diagnostics toggle<CR>', desc = 'Diagnostics (Trouble)' },
    { '<leader>xX', '<CMD>Trouble diagnostics toggle filter.buf=0<CR>', desc = 'Buffer diagnostics (Trouble)' },
  },
  after = function()
    require('trouble').setup {}
  end,
}
