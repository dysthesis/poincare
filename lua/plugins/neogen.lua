require('lz.n').load {
  'neogen',
  after = function()
    require('neogen').setup {}
  end,
  keys = {
    {
      '<leader>cg',
      function()
        require('neogen').generate()
      end,
      'Doc [C]omment [G]enerate',
    },
  },
}
