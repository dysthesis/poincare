require('lz.n').load {
  'neogit',
  cmd = 'Neogit',
  keys = {
    {
      '<leader>g',
      function()
        require('neogit').open { kind = 'auto' }
      end,
      desc = 'Neo[G]it',
    },
  },
  after = function()
    require('neogit').setup {
      graph_style = 'kitty',
    }
  end,
}
