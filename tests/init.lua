local mini_test = vim.env.MINI_TEST_RTP
local packpath = vim.env.POINCARE_PACKPATH

assert(mini_test and mini_test ~= "", "$MINI_TEST_RTP is not set")
assert(packpath and packpath ~= "", "$POINCARE_PACKPATH is not set")

local root =
  vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root .. "/src")
vim.opt.packpath:prepend(packpath)
vim.cmd.packadd("lz.n")
vim.opt.runtimepath:append(mini_test)

require("mini.test").setup({
  collect = {
    find_files = function()
      return {
        "tests/formatters.lua",
        -- tests/linters.lua targets a deferred built-in linter, not nvim-lint.
        "tests/statusline-diagnostic.lua",
      }
    end,
  },
})
