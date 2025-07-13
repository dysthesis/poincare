local picker = require('utils.notes_picker')

local sink = function(paths, key)
  local cmd = ({ ['ctrl-v'] = 'vsplit' })[key] or 'edit'
  local path = paths[#paths]
  if not path then
    return
  end
  local esc = vim.fn.fnameescape(path)
  vim.cmd(string.format('%s %s', cmd, esc))
end

local extra = ' --accept-nth=2'

local M = {}
M.open = function()
  picker.run(sink, extra)
end
return M
