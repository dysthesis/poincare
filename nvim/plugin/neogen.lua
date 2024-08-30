require('lz.n').load {
  'neogen',

  keys = {
    {
      '<leader>cc',
      function()
        require('neogen').generate()
      end,
      { noremap = true, silent = true },
      desc = '[C]ode generate documentation [C]omment',
    },
  },

  after = function()
    require('neogen').setup { snippet_engine = 'luasnip' }
  end,
}
