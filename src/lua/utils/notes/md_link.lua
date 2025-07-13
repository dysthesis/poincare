local M = {}
-- Percent-decode the path
function M.decode(str)
  return str:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end)
end
-- scan the current line for "[title](path)" spans
-- pick the one that contains the cursor
-- :edit that path
function M.follow()
  -- get cursor (row, 0-based col) and line text
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local c = col + 1 -- make it 1-based for pattern math

  local start = 1
  while true do
    -- look for the next markdown link
    local s, e, title, path = string.find(line, '%[([^]]+)%]%(([^)]+)%)', start)
    if not s then
      return -- no (more) links
    end
    -- is our cursor somewhere inside this “[...](...)”
    if c >= s and c <= e then
      local escaped = M.decode(path)
      vim.cmd('edit ' .. escaped)
      return
    end
    start = e + 1
  end
end
return M
