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
        config = function()
          -- centered on screen
          local height = math.floor(0.618 * vim.o.lines)
          local width = math.floor(0.618 * vim.o.columns)
          return {
            anchor = 'NW',
            border = 'rounded',
            height = height,
            width = width,
            row = math.floor(0.5 * (vim.o.lines - height)),
            col = math.floor(0.5 * (vim.o.columns - width)),
          }
        end,
      },
    }
  end,
}
