require('mini.icons').setup()
local lackluster = require('lackluster')
vim.api.nvim_set_hl(0, 'MiniIconsAzure', { fg = lackluster.color.lack })
vim.api.nvim_set_hl(0, 'MiniIconsBlue', { fg = lackluster.color.hint })
vim.api.nvim_set_hl(0, 'MiniIconsGreen', { fg = lackluster.color.special })
vim.api.nvim_set_hl(0, 'MiniIconsGrey', { fg = lackluster.color.gray4 })
vim.api.nvim_set_hl(0, 'MiniIconsPurple', { fg = '#cba6f7' })
vim.api.nvim_set_hl(0, 'MiniIconsOrange', { fg = lackluster.color.warn })
vim.api.nvim_set_hl(0, 'MiniIconsRed', { fg = lackluster.color.warn })
vim.api.nvim_set_hl(0, 'MiniIconsYellow', { fg = '#f9e2af' })
