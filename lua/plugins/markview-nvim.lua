require('lz.n').load {
  'markview.nvim',
  ft = 'markdown',
  after = function()
    require('markview').setup {
      markdown = {
        list_items = { shift_width = 2 },
        headings = require('markview.presets').headings.glow,
      },
      inline_codes = { hl = 'CursorColumn' },
      code_blocks = { border_hl = 'CursorColumn' },
    }
  end,
}
