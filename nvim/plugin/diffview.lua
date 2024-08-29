if vim.g.did_load_diffview_plugin then
  return
end
vim.g.did_load_diffview_plugin = true

vim.keymap.set('n', '<leader>gfb', function()
  vim.cmd.DiffviewFileHistory(vim.api.nvim_buf_get_name(0))
end, { desc = 'diffview [g]it [f]ile history (current [b]uffer)' })
vim.keymap.set('n', '<leader>Gfc', vim.cmd.DiffviewFileHistory, { desc = '[G]it [F]ile history ([C]WD)' })
vim.keymap.set('n', '<leader>Gd', vim.cmd.DiffviewOpen, { desc = '[G]it [D]iffview open' })
vim.keymap.set('n', '<leader>Gft', vim.cmd.DiffviewToggleFiles, { desc = '[G]it [D]iffview [F]iles [T]oggle' })
