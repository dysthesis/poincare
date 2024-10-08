require('lz.n').load {
  'neogit',
  cmd = 'Neogit',
  keys = { { '<leader>Gn', '<cmd>Neogit<cr>', desc = '[G]it [N]eogit' } },
  after = function()
    require('neogit').setup {
      integrations = {
        -- telescope = true,
        diffview = true,
      },
    }
  end,
}
