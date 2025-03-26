require('lz.n').load {
  'glance.nvim',
  keys = {
    { 'gD', '<CMD>Glance definitions<CR>' },
    { 'gR', '<CMD>Glance references<CR>' },
    { 'gY', '<CMD>Glance type_definitions<CR>' },
    { 'gM', '<CMD>Glance implementations<CR>' },
  },
  after = function()
    require('glance').setup {
      border = { enable = true },
    }
  end,
}
