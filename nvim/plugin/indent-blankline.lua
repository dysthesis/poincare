require('lz.n').load {
  'indent-blankline.nvim',
  event = 'BufReadPost',
  after = function()
    require('ibl').setup {
      exclude = {
        filetypes = {
          'dashboard',
        },
      },
    }
  end,
}
