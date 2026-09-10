local M = {}

M.hl_groups = {
  Name = {
    fg = { group = "Normal", attr = "fg" },
    bg = { group = "StatusLine", attr = "bg" },
  },

  Modified = {
    fg = { group = "DiagnosticWarn", attr = "fg" },
    bg = { group = "StatusLine", attr = "bg" },
  },
}

function M.component()
  local path = vim.api.nvim_buf_get_name(0)

  local name = path == "" and "[No Name]" or vim.fs.basename(path)

  local result = {
    "%#StatusLineName#",
    name,
  }

  if vim.bo.modified then
    table.insert(result, "%#StatusLineModified#")
    table.insert(result, " ●")
  end

  if vim.bo.readonly then
    result[#result + 1] = "%#StatusLineReadonly#"
    result[#result + 1] = " "
  end

  return table.concat(result)
end

return M
