local M = {}

M.hl_groups = {
  Lsp = {
    fg = { group = "LineNr", attr = "fg" },
    bg = { group = "StatusLine", attr = "bg" },
  },

  Error = {
    fg = { group = "DiagnosticError", attr = "fg" },
    bg = { group = "StatusLine", attr = "bg" },
  },

  Warn = {
    fg = { group = "DiagnosticWarn", attr = "fg" },
    bg = { group = "StatusLine", attr = "bg" },
  },

  Info = {
    fg = { group = "DiagnosticInfo", attr = "fg" },
    bg = { group = "StatusLine", attr = "bg" },
  },

  Hint = {
    fg = { group = "DiagnosticHint", attr = "fg" },
    bg = { group = "StatusLine", attr = "bg" },
  },
}

local severity = vim.diagnostic.severity

local diagnostic_icons = {
  [severity.ERROR] = { "", "StatusLineError" },
  [severity.WARN] = { "", "StatusLineWarn" },
  [severity.INFO] = { "", "StatusLineInfo" },
  [severity.HINT] = { "󰌵", "StatusLineHint" },
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
    table.concat(names, ","),
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
      local icon, hl = unpack(diagnostic_icons[level])

      result[#result + 1] = table.concat({
        "%#",
        hl,
        "#",
        icon,
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
