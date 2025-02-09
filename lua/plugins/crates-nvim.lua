require('lz.n').load {
  'crates.nvim',
  event = 'BufRead Cargo.toml',
  after = function()
    require('crates').setup {
      completion = {
        cmp = { enabled = true },
      },
    }
  end,
}
