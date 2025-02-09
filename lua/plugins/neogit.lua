require('lz.n').load {
  'neogit',
  cmd = 'Neogit',
  keys = {
    {
      '<leader>gg',
      function()
        require('neogit').open { kind = 'auto' }
      end,
      desc = '[G]it Neo[G]it',
    },
  },
  after = function()
    require('neogit').setup {
      graph_style = 'kitty',
    }
  end,
}
