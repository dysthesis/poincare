require('lz.n').load {
  'gitsigns.nvim',
  event = 'BufReadPost',
  after = function()
    require('gitsigns').setup {
      signs = {
        add = { text = '│' },
        change = { text = '│' },
        delete = { text = '󰍵' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
        untracked = { text = '┆' },
      },

      current_line_blame = true,

      on_attach = function(bufnr)
        local gs = package.loaded.gitsigns

        local function opts(desc)
          return { buffer = bufnr, desc = desc }
        end

        local map = vim.keymap.set

        map('n', '<leader>Grh', gs.reset_hunk, opts('Reset Hunk'))
        map('n', '<leader>Gh', gs.preview_hunk, opts('Preview Hunk'))
        map('n', '<leader>Gb', gs.blame_line, opts('Blame Line'))
      end,
    }
  end,
}
