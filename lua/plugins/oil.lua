require('lz.n').load {
  'oil.nvim',
  cmd = 'Oil',
  event = { 'VimEnter */*,.*', 'BufNew */*,.*' },
  keys = {
    {
      '<leader>.',
      '<cmd>Oil<cr>',
      'Open current working directory',
    },
  },
  after = function()
    require('oil').setup {
      skip_confirm_for_simple_edits = true,
      columns = {
        'icon',
        'permissions',
        'size',
        'mtime',
      },
    }
  end,
}
