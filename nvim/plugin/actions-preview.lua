-- require('lz.n').load {
--   'actions-preview.nvim',
--   keys = {
--     {
--       '<leader>ca',
--       function()
--         require('actions-preview').code_actions()
--       end,
--       desc = '[C]ode [A]ctions',
--     },
--   },
--   after = function()
--     require('actions-preview').setup {
--       highlight_command = {
--         require('actions-preview.highlight').delta('delta --hunk-header-style omit --paging=always'),
--       },
--     }
--   end,
-- }
