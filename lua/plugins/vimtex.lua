require('lz.n').load {
  'vimtex',
  lazy = false,
  before = function()
    vim.g.vimtex_view_method = 'zathura'
  end,
}
