local M = {}

function M.component()
  local name = vim.api.nvim_buf_get_name(0)

  return table.concat({
    "%#StatuslineMode" .. "Name" .. "#" .. name,
  })
end

return M
