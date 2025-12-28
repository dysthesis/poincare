require('lz.n').load {
  'inc-rename.nvim',
  cmd = 'IncRename',
  keys = {
    {
      '<leader>cr',
      function()
        local cmd = ':IncRename ' .. vim.fn.expand('<cword>')
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(cmd, true, false, true), 'n', false)
      end,
      desc = '[C]ode [R]ename',
    },
  },
  after = function()
    require('inc_rename').setup()
  end,
}
