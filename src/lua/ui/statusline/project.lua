local M = {}

M.hl_groups = {
  ProjectIcon = {
    fg = { group = "LineNr", attr = "fg" },
    bg = { group = "StatusLine", attr = "bg" },
  },

  Project = {
    fg = { group = "Normal", attr = "fg" },
    bg = { group = "StatusLine", attr = "bg" },
  },
}

function M.component()
  local root = vim.fs.root(0, {
    ".git",
    "flake.nix",
  })

  if not root then
    return ""
  end

  return table.concat({
    "%#StatusLineProjectIcon#",
    "󰉋",
    "%#StatusLineProject#",
    " ",
    vim.fs.basename(root),
  })
end

return M
