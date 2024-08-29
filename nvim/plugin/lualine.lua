require('lz.n').load {
  'lualine.nvim',
  event = 'DeferredUIEnter',
  before = function()
    vim.opt.laststatus = 0
  end,
  after = function()
    vim.opt.laststatus = 3
    require('lualine').setup {
      options = {
        component_separators = '',
        section_separators = { right = '', left = '' },
        disabled_filetypes = { 'alpha', 'neo-tree', 'TelescopePrompt' },
      },
      sections = {
        lualine_a = {
          {
            'mode',
            icon = { '󰹻 ' },
            separator = { right = '', left = '' },
            right_padding = 2,
          },
        },
        lualine_b = {
          'branch',
          {
            'diff',
            icon = { ' ' },
            symbols = { added = ' ', modified = ' ', removed = ' ' },
          },
          'diagnostics',
        },
        lualine_c = {
          {
            'filename',
            icon = { '  ' },
          },
        },
        lualine_x = {
          'filetype',
        },
        lualine_z = {
          {
            'location',
            icon = { '', align = 'left' },
          },
          {
            'progress',
            icon = { '', align = 'left' },
            separator = { right = '', left = '' },
          },
        },
      },
      extensions = { 'nvim-tree', 'fzf' },
    }
  end,
}
