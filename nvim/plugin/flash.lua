require('lz.n').load {
  'flash.nvim',

  event = 'DeferredUIEnter',

  keys = {
    {
      's',
      function()
        require('flash').jump()
      end,
      { mode = { 'n', 'x', 'o' }, desc = 'Flash forward to' },
    },

    {
      'S',
      function()
        require('flash').jump { forward = false }
      end,
      { mode = { 'n', 'x', 'o' }, desc = 'Flash backward to' },
    },

    {
      't',
      function()
        require('flash').treesitter()
      end,
      { mode = { 'n', 'x', 'o' }, desc = 'Flash forward to' },
    },

    {
      'T',
      function()
        require('flash').treesitter_search()
      end,
      { mode = { 'n', 'x', 'o' }, desc = 'Flash backward to' },
    },

    {
      '<leader>tf',
      function()
        require('flash').toggle()
      end,
      { mode = { 'n', 'x', 'o' }, desc = '[T]oggle [F]lash search' },
    },
  },

  after = function()
    require('flash').setup()
  end,
}
