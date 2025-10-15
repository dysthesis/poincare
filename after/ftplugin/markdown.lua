-- local function map(mode, l, r, opts)
--   opts = opts or {}
--   vim.keymap.set(mode, l, r, opts)
-- end
--
-- map('n', '<leader>or', function()
--   require('utils.references').open_reference(0)
-- end, { buffer = true, silent = true, desc = 'Open front-matter reference' })
vim.opt_local.wrap = true
vim.opt_local.smoothscroll = true
vim.opt_local.linebreak = true
vim.opt_local.breakindent = true
