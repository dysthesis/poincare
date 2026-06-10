-- Scenario: :write a lua buffer; cost = BufWritePre load of conform.nvim.
-- Writes a throwaway copy in TMPDIR, never the fixture. The formatter
-- binary (stylua) is intentionally absent from the closure, so this
-- measures conform's load + dispatch, not stylua itself.
local here = vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))
local run = dofile(here .. '/_run.lua')

run('write', function(files)
  local dst = vim.fn.tempname() .. '.lua'
  vim.fn.writefile(vim.fn.readfile(files .. '/big.lua'), dst)
  vim.cmd('silent! edit ' .. vim.fn.fnameescape(dst))
  vim.api.nvim_buf_set_lines(0, 0, 0, false, { '-- touched by bench write scenario' })
  vim.cmd('silent! write')
  assert(package.loaded['conform'] ~= nil, 'conform did not load on BufWritePre')
end)
