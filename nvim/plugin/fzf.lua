require('lz.n').load {
  'fzf-lua',
  keys = {
    -- Searching
    {
      '<leader>ff',
      function()
        require('fzf-lua').files()
      end,
      desc = '[F]ind [F]iels',
    },
    {
      '<leader>fh',
      function()
        require('fzf-lua').help()
      end,
      desc = '[F]ind [H]elp',
    },
    {
      '<leader>fg',
      function()
        require('fzf-lua').live_grep_native()
      end,
      desc = '[F]ind [G]rep',
    },
    {
      '<leader>fq',
      function()
        require('fzf-lua').quickfix()
      end,
      desc = '[F]ind [Q]uickfix',
    },
  },
  after = function()
    require('fzf-lua').setup {
      'fzf-native',
      fzf_colors = true,
      keymap = {
        builtin = {
          ['<M-k>'] = 'preview-page-up',
          ['<M-j>'] = 'preview-page-down',
        },
        fzf = {
          ['alt-k'] = 'preview-page-up',
          ['alt-j'] = 'preview-page-down',
        },
        code_actions = {
          previewer = 'codeaction_native',
          preview_pager = 'delta --side-by-side --width=$FZF_PREVIEW_COLUMNS',
        },
      },
    }
  end,
}
