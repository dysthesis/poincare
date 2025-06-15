require('lz.n').load {
  'crates.nvim',
  event = 'BufRead Cargo.toml',
  after = function()
    require('crates').setup {
      lsp = {
        enabled = true,
        actions = true,
        completion = true,
        hover = true,
      },
    }
  end,
}
