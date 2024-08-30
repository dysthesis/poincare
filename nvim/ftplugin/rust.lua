-- Load neotest module
local neotest_loaded, neotest = pcall(require, 'neotest')

if neotest_loaded then
  neotest.setup {
    adapters = {
      require('rustaceanvim.neotest'),
    },
  }
end
