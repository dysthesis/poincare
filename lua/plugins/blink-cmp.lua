require('lz.n').load {
  'blink.cmp',
  event = 'InsertEnter',
  after = function()
    require('blink.cmp').setup {
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 0, window = { border = 'single' } },
        ghost_text = { enabled = true },
        menu = {
          border = 'single',
          -- Use mini.icons
          draw = {
            components = {
              kind_icon = {
                ellipsis = false,
                text = function(ctx)
                  local kind_icon, _, _ = require('mini.icons').get('lsp', ctx.kind)
                  return kind_icon
                end,
                -- Optionally, you may also use the highlights from mini.icons
                highlight = function(ctx)
                  local _, hl, _ = require('mini.icons').get('lsp', ctx.kind)
                  return hl
                end,
              },
            },
          },
        },
      },
      appearance = { use_nvim_cmp_as_default = false },
      signature = { enabled = true },

      -- Pick sources depending on file type and/or tree-sitter node
      sources = {
        default = function(ctx)
          local success, node = pcall(vim.treesitter.get_node)
          if vim.bo.filetype == 'lua' then
            return { 'lsp', 'path' }
          elseif success and node and vim.tbl_contains({ 'comment', 'line_comment', 'block_comment' }, node:type()) then
            return { 'buffer' }
          else
            return { 'lsp', 'path', 'snippets', 'buffer' }
          end
        end,
      },
    }
  end,
}
