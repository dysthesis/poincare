-- Scenario: open a representative rust file; cost = ft trigger loads
-- (treesitter assets, gitsigns, nvim-lint, ...) + highlighter activation.
local here = vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))
local run = dofile(here .. '/_run.lua')

run('open-rust', function(files)
  vim.cmd('silent! edit ' .. vim.fn.fnameescape(files .. '/big.rs'))
  local buf = vim.api.nvim_get_current_buf()
  vim.wait(10000, function()
    return vim.treesitter.highlighter.active[buf] ~= nil
  end, 10)
  assert(vim.treesitter.highlighter.active[buf], 'treesitter highlighter never became active')
end)
