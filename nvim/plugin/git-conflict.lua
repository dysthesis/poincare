require('lz.n').load {
  'git-conflict.nvim',
  event = { 'BufNew', 'BufReadPre' },
  after = function()
    local gc = require('git-conflict')

    gc.setup {}

    -- local group = vim.api.nvim_create_augroup('GitConflict', { clear = true })
    --
    -- vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost' }, {
    --   group = group,
    --   callback = function(args)
    --     local buf = args.buf
    --     gc.refresh(buf)
    --   end,
    -- })
  end,
}
