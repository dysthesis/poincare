require('lz.n').load {
  'markview.nvim',
  ft = 'markdown',
  after = function()
    require('markview').setup {
      modes = { 'n', 'i', 'no', 'c' },
      hybrid_modes = { 'i' },

      -- This is nice to have
      callbacks = {
        on_enable = function(_, win)
          vim.wo[win].conceallevel = 2
          vim.wo[win].concealcursor = 'nc'
        end,
      },
      headings = {
        enable = true,
        shift_width = 0,

        heading_1 = { icon = ' 󰫈 ' },
        heading_2 = { icon = ' 󰫇 ' },
        heading_3 = { icon = ' 󰫆 ' },
        heading_4 = { icon = ' 󰫅 ' },
        heading_5 = { icon = ' 󰫄 ' },
        heading_6 = { icon = ' 󰫃 ' },
      },
      code_blocks = { hl = 'CursorColumn' },
      inline_codes = { hl = 'CursorColumn' },
      list_items = { shift_width = 2 },
    }
  end,
}
