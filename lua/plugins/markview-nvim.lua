require('lz.n').load {
  'markview.nvim',
  ft = 'markdown',
  after = function()
    require('markview').setup {
      markdown = {
        list_items = { shift_width = 2 },
        headings = {
          ---+ ${conf, Glow-like headings}
          enable = true,
          shift_width = 0,

          heading_1 = {
            style = 'label',
            sign = '󰌕 ',
            sign_hl = 'MarkviewHeading1Sign',

            padding_left = ' ',
            padding_right = ' ',
            icon = '󰫈 ',
            hl = 'MarkviewHeading1',
          },
          heading_2 = {
            style = 'label',
            sign = '󰌖 ',
            sign_hl = 'MarkviewHeading2Sign',

            padding_left = ' ',
            padding_right = ' ',
            icon = '󰫇 ',
            hl = 'MarkviewHeading2',
          },
          heading_3 = {
            style = 'label',

            padding_left = ' ',
            padding_right = ' ',
            icon = '󰫆 ',
            hl = 'MarkviewHeading3',
          },
          heading_4 = {
            style = 'label',

            padding_left = ' ',
            padding_right = ' ',
            icon = '󰫅 ',
            hl = 'MarkviewHeading4',
          },
          heading_5 = {
            style = 'label',

            padding_left = ' ',
            padding_right = ' ',
            icon = '󰫄 ',
            hl = 'MarkviewHeading5',
          },
          heading_6 = {
            style = 'label',

            padding_left = ' ',
            padding_right = ' ',
            icon = '󰫃 ',
            hl = 'MarkviewHeading6',
          },
          ---_
        },
      },
      inline_codes = { hl = 'CursorColumn' },
      code_blocks = { border_hl = 'CursorColumn' },
    }
  end,
}
