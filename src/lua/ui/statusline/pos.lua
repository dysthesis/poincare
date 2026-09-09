local M = {}

function M.component()
  local row = vim.fn.line(".")
  local col = vim.fn.virtcol(".")
  local total = vim.fn.line("$")

  local percent
  if total <= 1 then
    percent = 100
  else
    percent = math.floor(((row - 1) / (total - 1)) * 100)
  end

  return table.concat({
    "%#StatusLinePosIcon#",
    "󰍉",
    "%#StatusLinePos#",
    " ",
    row,
    ":",
    col,
    "  ",
    percent,
    "%%",
  })
end

return M
