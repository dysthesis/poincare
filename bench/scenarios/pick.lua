-- Scenario: <leader>f opens the file picker; cost = mini.pick + mini.extra
-- + icons. The <Esc> rides in the same typeahead so the picker's input loop
-- consumes it and returns; the deferred stop() is a safety net in case the
-- picker swallows the <Esc> (e.g. an intermediate prompt).
local here = vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))
local run = dofile(here .. '/_run.lua')

run('pick', function()
  vim.defer_fn(function()
    pcall(function()
      require('mini.pick').stop()
    end)
  end, 500)
  local keys = vim.api.nvim_replace_termcodes(' f<Esc>', true, false, true)
  vim.fn.feedkeys(keys, 'mx')
  assert(package.loaded['mini.pick'] ~= nil, 'mini.pick did not load on <leader>f')
end)
