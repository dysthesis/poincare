local core = require('utils.picker')

local M = {}

M.open = function()
  core.run {
    producer = "rg --files --hidden --follow --glob '!.git/*'", -- fast file list
    preview = 'bat --style=numbers --color=always {}', -- colourful view
    parse = function(lines)
      return lines
    end, -- identity parse
    sink = function(paths, key)
      local cmd = ({ ['ctrl-v'] = 'vsplit' })[key] or 'edit'
      for _, p in ipairs(paths) do
        vim.cmd(cmd .. ' ' .. vim.fn.fnameescape(p))
      end
    end,
  }
end

return M
