require('lz.n').load {
  'inc-rename.nvim',
  cmd = 'IncRename',
  keys = {
    {
      '<leader>cr',
      ':IncRename ',
      desc = '[C]ode [R]ename',
    },
  },
  after = function()
    require('inc_rename').setup()
  end,
}
