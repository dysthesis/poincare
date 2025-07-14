require('lz.n').load {
  'mini.surround',
  event = 'BufReadPost',
  after = function()
    require('mini.surround').setup {
      mappings = {
        add = 'S', -- Add surrounding in Normal and Visual modes
        delete = 'ds', -- Delete surrounding
        replace = 'cs', -- Replace surrounding
      },
    }
  end,
}
