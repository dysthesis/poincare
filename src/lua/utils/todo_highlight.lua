local cmd = vim.cmd
local api = vim.api

-- Create an augroup for comment-scoped TODO highlighting
api.nvim_create_augroup('SyntaxTodoColours', { clear = true })

api.nvim_create_autocmd('Syntax', {
  group = 'SyntaxTodoColours',
  callback = function()
    -- Define four separate syntax matches, all constrained to comment regions
    cmd([[
      " Our items must be 'contained' so that the `containedin=` clause is honoured
      syntax keyword MyTodo  TODO             contained containedin=.*Comment
      syntax keyword MyFix   FIXME BUG        contained containedin=.*Comment
      syntax keyword MyPerf  PERF             contained containedin=.*Comment
      syntax keyword MyNote  NOTE             contained containedin=.*Comment
    ]])

    -- Link or set highlight for each group
    -- TODO keeps your default Todo color
    api.nvim_set_hl(0, 'MyTodo', { link = 'Todo', default = true, bold = true })
    -- FIXME & BUG in red
    api.nvim_set_hl(0, 'MyFix', { fg = '#FFAA88', bold = true, default = true })
    -- PERF in green
    api.nvim_set_hl(0, 'MyPerf', { fg = '#789978', default = true, bold = true })
    -- NOTE in cyan
    api.nvim_set_hl(0, 'MyNote', { fg = '#7788AA', default = true, bold = true })
  end,
})
