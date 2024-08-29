require('lz.n').load {
  'ultimate-autopair.nvim',
  event = { 'InsertEnter', 'CmdlineEnter' },
  after = function()
    require('ultimate-autopair').setup()
  end,
}
