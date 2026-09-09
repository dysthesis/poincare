local M = {}

M.hl_groups = {
  FtIcon = {
    fg = { group = "LineNr", attr = "fg" },
    bg = { group = "StatusLine", attr = "bg" },
  },

  Ft = {
    fg = { group = "Normal", attr = "fg" },
    bg = { group = "StatusLine", attr = "bg" },
  },
}

local icons = {
  lua = "",
  nix = "󱄅",
  rust = "",
  go = "",
  python = "",
  javascript = "",
  typescript = "",
  markdown = "",
  json = "",
  yaml = "",
  toml = "",
  sh = "",
  bash = "",
  zsh = "",
  c = "",
  cpp = "",
  zig = "",
  typst = "",
}

function M.component()
  local ft = vim.bo.filetype

  if ft == "" then
    return ""
  end

  local icon = icons[ft] or ""

  return table.concat({
    "%#StatusLineFtIcon#",
    icon,
    "%#StatusLineFt#",
    " ",
    ft,
  })
end

return M
