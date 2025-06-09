require('lz.n').load {
  'typst-preview.nvim',
  ft = 'typst',
  after = function()
    require('typst-preview').setup {
      open_cmd = 'zen %s -P typst-preview --class typst-preview',
    }
  end,
}
