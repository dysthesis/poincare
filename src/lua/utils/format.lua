vim.api.nvim_create_augroup('AutoFormat', {})

vim.api.nvim_create_autocmd('BufWritePost', {
  pattern = '**.nix',
  group = 'AutoFormat',
  callback = function()
    vim.cmd('silent !alejandra -qq %')
    vim.cmd('edit')
  end,
})

vim.api.nvim_create_autocmd('BufWritePost', {
  pattern = '**.rs',
  group = 'AutoFormat',
  callback = function()
    vim.cmd('silent !cargo fmt')
    vim.cmd('edit')
  end,
})
vim.api.nvim_create_autocmd('BufWritePost', {
  pattern = '**.lua',
  group = 'AutoFormat',
  callback = function()
    local name = vim.api.nvim_buf_get_name(0)
    vim.cmd(':silent :!stylua ' .. name)
  end,
  group = autocmd_group,
})
