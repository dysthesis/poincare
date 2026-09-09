local mini_test = vim.env.MINI_TEST_RTP

assert(mini_test and mini_test ~= "", "$MINI_TEST_RTP is not set")
vim.opt.runtimepath:append(mini_test)

require("mini.test").setup({
  collect = {
    find_files = function()
      return { "tests/formatters.lua" }
    end,
  },
})
