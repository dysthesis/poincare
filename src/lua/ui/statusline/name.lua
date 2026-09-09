local M = {}

M.hl_groups = {
  Name = {
    fg = { group = "Normal", attr = "fg" },
    bg = { group = "StatusLine", attr = "bg" },
  },
}

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
