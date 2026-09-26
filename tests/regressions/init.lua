-- This runs after normal startup of the *working-tree* src/init.lua. Do not
-- use --clean or --noplugin: those change filetype and lazy-load ordering.
local cases = {
  statusline = "tests/regressions/statusline.lua",
  sqlite = "tests/regressions/sqlite.lua",
  first_lint = "tests/regressions/first-lint.lua",
  first_lint_cli = "tests/regressions/first-lint.lua",
}

local name = vim.env.POINCARE_TEST_CASE
assert(
  cases[name],
  "set POINCARE_TEST_CASE to statusline, sqlite, first_lint or first_lint_cli"
)
assert(
  vim.env.MINI_TEST_RTP and vim.env.MINI_TEST_RTP ~= "",
  "MINI_TEST_RTP is required"
)
assert(
  vim.env.POINCARE_PACKPATH and vim.env.POINCARE_PACKPATH ~= "",
  "POINCARE_PACKPATH is required"
)

require("mini.test").setup({
  collect = {
    find_files = function()
      return { cases[name] }
    end,
  },
})

MiniTest.run()
