-- Based on https://jacobnscott.com/posts/nvim-statusline/
local M = {}

function M.render()
  local active = vim.fn.win_getid()
  local status = tonumber(vim.g.actual_curwin)

  if status ~= active then
    return "Statusline for inactive windows"
  end

  return table.concat({
    "Statusline left-aligned stuff",
    "%=", -- Left/right separator
    "Statusline right-aligned stuff",
  })
end

return M
