-- Scenario: enter insert mode and type; cost = InsertEnter loads
-- (blink.cmp incl. its prebuilt fuzzy lib, ultimate-autopair).
local here = vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))
local run = dofile(here .. '/_run.lua')

run('insert', function()
  vim.cmd.enew()
  local keys = vim.api.nvim_replace_termcodes('ilocal x = 1<Esc>', true, false, true)
  vim.fn.feedkeys(keys, 'mx')
  assert(package.loaded['blink.cmp'] ~= nil, 'blink.cmp did not load on InsertEnter')
end)
