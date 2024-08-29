-- disable netrw at the very start of your init.lua
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

require('lz.n').load {
  'neo-tree.nvim',
  cmd = 'Neotree',
  load = function(name)
    vim.cmd.packadd(name)
    vim.cmd.packadd('plenary.nvim')
    vim.cmd.packadd('nvim-web-devicons')
    vim.cmd.packadd('nui.nvim')
  end,

  keys = {
    { '\\', '<cmd>Neotree toggle<cr>', desc = 'Toggle Neotree' },
  },
  after = function()
    require('neo-tree').setup()
  end,
}
