require('lz.n').load {
  'toggleterm.nvim',
  cmd = 'ToggleTerm',
  keys = {
    { '<leader>tt', '<CMD>ToggleTerm direction=float<CR>', desc = '[T]oggle [T]erm' },
  },
  after = function()
    require('toggleterm').setup {}
  end,
}
