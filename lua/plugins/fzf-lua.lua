require('lz.n').load {
  'fzf-lua',
  cmd = 'FzfLua',
  keys = {
    {
      '<leader>ff',
      function()
        require('fzf-lua').files()
      end,
      desc = '[F]ind [F]iles',
    },
    {
      '<leader>fg',
      function()
        require('fzf-lua').live_grep_native()
      end,
      desc = '[F]ind [G]rep',
    },
    {
      '<leader>fh',
      function()
        require('fzf-lua').helptags()
      end,
      desc = '[F]ind [G]rep',
    },
    {
      '<leader>fr',
      function()
        require('fzf-lua').lsp_references()
      end,
      desc = '[F]ind [R]eferences',
    },
    {
      '<leader>fd',
      function()
        require('fzf-lua').lsp_definitions()
      end,
      desc = '[F]ind [D]efinitions',
    },
    {
      '<leader>fy',
      function()
        require('fzf-lua').lsp_typedefs()
      end,
      desc = '[F]ind t[Y]pe definitions',
    },
  },
}
