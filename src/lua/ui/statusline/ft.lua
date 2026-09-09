local M = {}

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
