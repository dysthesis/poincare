require('lz.n').load {
  'oil.nvim',
  cmd = 'Oil',
  event = { 'VimEnter */*,.*', 'BufNew */*,.*' },
  after = function()
    require('oil').setup {
      view_options = {
        show_hidden = true,
      },
    }
  end,
}
