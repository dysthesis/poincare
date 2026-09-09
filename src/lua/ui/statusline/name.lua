local M = {}

function M.component()
  local path = vim.api.nvim_buf_get_name(0)

  local name
  if path == "" then
    name = "[No Name]"
  else
    name = vim.fs.basename(path)
  end

  return "%#StatusLineName#" .. name
end

return M
