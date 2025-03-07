require('lz.n').load {
  'mini.snippets',
  event = 'InsertEnter',
  after = function()
    local gen_loader = require('mini.snippets').gen_loader
    require('mini.snippets').setup {
      snippets = { gen_loader.from_lang() },
    }
  end,
}
