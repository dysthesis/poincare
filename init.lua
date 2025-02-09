-- Load configurations
require('config.keys')
require('config.ui')
require('config.behaviour')
require('config.statusline')
require('config.lsp')

vim.cmd.filetype('plugin', 'indent', 'on')
vim.cmd.packadd('cfilter') -- Allows filtering the quickfix list with :cfdo

require('packages')
