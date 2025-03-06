require('lz.n').load {
  'noice.nvim',
  event = 'DeferredUIEnter',
  after = function()
    require('noice').setup {
      views = {
        cmdline_popup = {
          position = {
            row = 20,
            col = '50%',
          },
          size = {
            min_width = 60,
            width = 'auto',
            height = 'auto',
          },
        },
        popupmenu = {
          relative = 'editor',
          position = {
            row = 23,
            col = '50%',
          },
          size = {
            width = 60,
            height = 'auto',
            max_height = 15,
          },
          border = {
            style = 'rounded',
            padding = { 0, 1 },
          },
          win_options = {
            winhighlight = { Normal = 'Normal', FloatBorder = 'NoiceCmdlinePopupBorder' },
          },
        },
      },
      -- add any options here
      lsp = {
        override = {
          ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
          ['vim.lsp.util.stylize_markdown'] = true,
          ['cmp.entry.get_documentation'] = true, -- requires hrsh7th/nvim-cmp
        },
      },
      -- you can enable a preset for easier configuration
      presets = {
        bottom_search = false, -- use a classic bottom cmdline for search
        command_palette = true, -- position the cmdline and popupmenu together
        long_message_to_split = true, -- long messages will be sent to a split
        inc_rename = true, -- enables an input dialog for inc-rename.nvim
        lsp_doc_border = true, -- add a border to hover docs and signature help
      },
    }
  end,
}
