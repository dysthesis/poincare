vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Clear highlights on search when pressing <Esc> in normal mode
--  See `:help hlsearch`
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Diagnostic keymaps
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

-- Move lines up and down
local function map(mode, l, r, opts)
  opts = opts or {}
  vim.keymap.set(mode, l, r, opts)
end
map('n', '<A-J>', ':m .+1<CR>==') -- move line up(n)
map('n', '<A-K>', ':m .-2<CR>==') -- move line down(n)
map('v', '<A-J>', ":m '>+1<CR>gv=gv") -- move line up(v)
map('v', '<A-K>', ":m '<-2<CR>gv=gv") -- move line down(v)

vim.keymap.set('v', '<Tab>', '>gv', { noremap = true, silent = true })
vim.keymap.set('v', '<S-Tab>', '<gv', { noremap = true, silent = true })

map('n', '<leader>f', function()
  require('utils.file_picker').open()
end)

map('n', '<leader>g', function()
  require('utils.live_grep').open()
end)

map('n', '<leader>n', function()
  require('utils.notes_edit').open()
end)

map('n', '<leader>i', function()
  require('utils.notes_link_insert').open()
end)

map('n', '<leader>b', function()
  require('utils.notes_backlinks_edit').open()
end)

map('n', '<leader>B', function()
  require('utils.notes_backlinks_insert').open()
end)

map('i', '<A-i>', function()
  require('utils.notes_link_insert').open()
end)

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'markdown',
  callback = function()
    vim.keymap.set('n', '<S-CR>', function()
      require('utils.md_link').follow()
    end, { buffer = true, silent = true, desc = 'Follow markdown link' })
  end,
})
