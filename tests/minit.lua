-- Parent entry point for the behavioural suite. Must run inside the wrapped
-- poincare binary so the children inherit the exact store paths under test:
--   <poincare>/bin/nvim --headless "+luafile tests/minit.lua"
local source = debug.getinfo(1, 'S').source:sub(2)
local tests_dir = vim.fs.dirname(vim.uv.fs_realpath(source) or source)

package.path = table.concat({ tests_dir .. '/?.lua', package.path }, ';')

local function die(message)
  vim.api.nvim_err_writeln(message)
  vim.cmd('cquit 1')
end

-- MINI_TEST_PATH lets the suite run against builds that predate mini.test
-- in the closure (red/green verification across revisions).
local function ensure_mini_test()
  -- packadd of a missing package does not reliably error; gate on require.
  pcall(vim.cmd.packadd, 'mini.test')
  if pcall(require, 'mini.test') then
    return true
  end
  if vim.env.MINI_TEST_PATH ~= nil and vim.env.MINI_TEST_PATH ~= '' then
    vim.opt.runtimepath:prepend(vim.env.MINI_TEST_PATH)
    return (pcall(require, 'mini.test'))
  end
  return false
end

if not ensure_mini_test() then
  die('mini.test is neither in the packpath nor reachable via MINI_TEST_PATH')
end

local minitest = require('mini.test')

minitest.setup {
  collect = {
    find_files = function()
      local files = vim.fn.globpath(tests_dir, 'test_*.lua', true, true)
      table.sort(files)
      return files
    end,
  },
}

-- Case failures are collected by mini.test itself (the stdout reporter quits
-- with a non-zero exit code); this xpcall only catches collection-time
-- crashes, which would otherwise leave a headless Neovim hanging.
local run_ok, run_err = xpcall(function()
  minitest.run {
    execute = {
      reporter = minitest.gen_reporter.stdout { quit_on_finish = true },
    },
  }
end, debug.traceback)
if not run_ok then
  die('test run crashed:\n' .. tostring(run_err))
end
