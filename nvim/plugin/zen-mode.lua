require('lz.n').load {
  'zen-mode.nvim',
  load = function(name)
    vim.cmd.packadd(name)
    vim.cmd.packadd('twilight')
  end,
  keys = {
    { '<leader>tz', '<CMD>ZenMode<CR>', desc = '[T]oggle [Z]en' },
  },
  after = function()
    require('zen-mode').setup {
      twilight = {
        enabled = true,
      },
      -- tmux = {
      --   enabled = false,
      -- },
      wezterm = {
        enabled = true,
      },
    }
  end,
}
