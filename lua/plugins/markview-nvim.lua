require('lz.n').load {
  'markview.nvim',
  ft = 'markdown',
  after = function()
    require('markview').setup {
      headings = require('markview.presets').headings.glow,
      code_blocks = { hl = 'CursorColumn' },
      inline_codes = { hl = 'CursorColumn' },
      list_items = { shift_width = 2 },
    }
  end,
}
