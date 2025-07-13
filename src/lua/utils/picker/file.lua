local picker = require('utils.picker.core')

local M = {}

local function strip_ansi(s)
  return (s:gsub('\27%[[0-9;]*m', ''))
end

M.open = function()
  picker.run {
    producer = [=[
      rg --files --hidden --follow --glob '!.git/*' | while IFS= read -r path; do
        basename="${path##*/}"
        dirname="${path%/*}"
        
        if [ "$dirname" = "$path" ]; then
          echo "$(tput bold)$basename$(tput sgr0)"
        else
          echo "$(tput setaf 244)$dirname/$(tput sgr0)$(tput bold)$basename$(tput sgr0)"
        fi
      done \
    ]=],
    preview = 'bat --style=numbers --color=always {}',
    parse = function(lines)
      local out = {}
      for _, l in ipairs(lines) do
        table.insert(out, strip_ansi(l))
      end
      return out
    end,
    sink = function(paths, key)
      local cmd = ({ ['ctrl-v'] = 'vsplit' })[key] or 'edit'
      for _, p in ipairs(paths) do
        vim.cmd(cmd .. ' ' .. vim.fn.fnameescape(p))
      end
    end,
  }
end

return M
