-- M.based on https://jacobnscott.com/posts/nvim-statusline/
local M = {}

function M.hl(group)
  return vim.api.nvim_get_hl(0, {
    name = group,
    link = false,
    create = false,
  })
end

M.base = M.hl("StatusLine")

M.hl_groups = {
  ModeNormal = { fg = M.base.bg, bg = M.hl("StatusLine").fg },
  ModePending = { fg = M.base.bg, bg = M.hl("Comment").fg },
  ModeVisual = { fg = M.base.bg, bg = M.hl("SpecialKey").fg },
  ModeInsert = { fg = M.base.bg, bg = M.hl("DiffAdded").fg },
  ModeCommand = { fg = M.base.bg, bg = M.hl("Number").fg },
  ModeReplace = { fg = M.base.bg, bg = M.hl("Constant").fg },
  Bold = { fg = M.base.fg, bg = M.base.bg, bold = true },
  Dim = { fg = M.hl("LineNr").fg, bg = M.base.bg },
}

function M.set_hl_groups()
  for group, opts in pairs(M.hl_groups) do
    group = "StatusLine" .. group
    vim.api.nvim_set_hl(0, group, opts)
    opts.fg, opts.bg = opts.bg, opts.fg
    vim.api.nvim_set_hl(0, group .. "Inverted", opts)
  end
end

M.set_hl_groups()

-- Re-compile statusline colours when the colorscheme changes
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("my_statusline", {}),
  desc = "Re-apply statusline highlights on colorscheme change",
  callback = M.set_hl_groups,
})

function M.render()
  local active = vim.fn.win_getid()
  local status = tonumber(vim.g.actual_curwin)

  if status ~= active then
    return "Statusline for inactive windows"
  end

  return table.concat({
    require("ui.statusline.mode").component(),
    "%=", -- Left/right separator
    "Statusline right-aligned stuff",
  })
end

return M
