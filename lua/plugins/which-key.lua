require('lz.n').load {
  'which-key.nvim',
  event = 'DeferredUIEnter',
  keys = {
    {
      '<leader>?',
      function()
        require('which-key').show { global = false }
      end,
      desc = 'Buffer Local Keymaps (which-key)',
    },
  },
}
