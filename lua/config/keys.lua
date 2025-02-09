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
