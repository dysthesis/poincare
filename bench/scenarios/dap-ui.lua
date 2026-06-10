-- Scenario: <leader>Do opens the DAP UI; cost = nvim-dap-ui -> (via
-- trigger_load) nvim-dap + nvim-nio + virtual-text, adapter and listener
-- setup, element buffer creation. The heaviest deferred chain in the config.
local here = vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))
local run = dofile(here .. '/_run.lua')

run('dap-ui', function()
  local keys = vim.api.nvim_replace_termcodes(' Do', true, false, true)
  vim.fn.feedkeys(keys, 'mx')
  assert(package.loaded['dapui'] ~= nil, 'nvim-dap-ui did not load on <leader>Do')
  assert(require('dap').adapters.codelldb ~= nil, 'codelldb adapter not configured (bug 5 regression)')
end)
