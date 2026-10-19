local M = {}
local literal = require("ui.statusline.text")
local severity = vim.diagnostic.severity

local severity_groups = {
  [severity.ERROR] = "Error",
  [severity.WARN] = "Warn",
  [severity.INFO] = "Info",
  [severity.HINT] = "Hint",
}

M.hl_groups = {
  Lsp = {
    fg = { group = "Conceal", attr = "fg" },
    bg = { group = "StatusLine", attr = "bg" },
  },
}

for _, group in pairs(severity_groups) do
  M.hl_groups[group] = {
    fg = { group = "Diagnostic" .. group, attr = "fg" },
    bg = { group = "StatusLine", attr = "bg" },
  }
end

local diagnostic_icons = {
  [severity.ERROR] = "",
  [severity.WARN] = "",
  [severity.INFO] = "",
  [severity.HINT] = "󰌵",
}

local function lsp()
  local clients = vim.lsp.get_clients({ bufnr = 0 })

  if #clients == 0 then
    return nil
  end

  local names = {}

  for _, client in ipairs(clients) do
    names[#names + 1] = client.name
  end

  table.sort(names)

  return table.concat({
    "%#StatusLineLsp#",
    " ",
    literal(table.concat(names, ",")),
  })
end

local function diagnostics()
  local counts = vim.diagnostic.count(0)
  local result = {}

  for _, level in ipairs({
    severity.ERROR,
    severity.WARN,
    severity.INFO,
    severity.HINT,
  }) do
    local count = counts[level] or 0

    if count > 0 then
      result[#result + 1] = table.concat({
        "%#StatusLine",
        severity_groups[level],
        "#",
        diagnostic_icons[level],
        " ",
        count,
      })
    end
  end

  if #result == 0 then
    return nil
  end

  return table.concat(result, " ")
end

function M.component()
  local result = {}

  local lsp_status = lsp()
  if lsp_status then
    result[#result + 1] = lsp_status
  end

  local diagnostic_status = diagnostics()
  if diagnostic_status then
    result[#result + 1] = diagnostic_status
  end

  return table.concat(result, " ")
end

return M
