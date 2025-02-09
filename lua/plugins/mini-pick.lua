require('lz.n').load {
  'mini.pick',
  cmd = 'Pick',
  keys = {
    {
      '<leader>ff',
      function()
        require('mini.pick').builtin.files()
      end,
      desc = '[F]ind [F]iles',
    },
    {
      '<leader>fg',
      function()
        require('mini.pick').builtin.grep_live()
      end,
      desc = '[F]ind [G]rep',
    },
    {
      '<leader>fh',
      function()
        require('mini.pick').builtin.help()
      end,
      desc = '[F]ind [G]rep',
    },
  },
  after = function()
    require('mini.pick').setup {
      options = {
        use_cache = true,
      },
      window = {
        prompt_prefix = '   ',
      },
    }
  end,
}
