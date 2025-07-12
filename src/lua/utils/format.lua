vim.api.nvim_create_augroup('AutoFormat', {})

vim.api.nvim_create_autocmd('BufWritePost', {
  pattern = '*.nix',
  group = 'AutoFormat',
  callback = function()
    vim.cmd('silent !alejandra -qq %')
    vim.cmd('edit')
  end,
})

vim.api.nvim_create_autocmd('BufWritePost', {
  pattern = '*.rs',
  group = 'AutoFormat',
  callback = function()
    vim.cmd('silent !cargo fmt')
    vim.cmd('edit')
  end,
})
