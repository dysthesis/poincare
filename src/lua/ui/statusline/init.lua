-- M.based on https://jacobnscott.com/posts/nvim-statusline/
local M = {}

function M.hl(group)
  return vim.api.nvim_get_hl(0, {
    name = group,
    link = false,
    create = false,
  })
end

local function ref(group, attr)
  return { group = group, attr = attr }
end

M.hl_groups = {
  Mode = {
    fg = ref("PmenuSel", "fg"),
    bg = ref("StatusLine", "bg"),
    bold = true,
  },

  Name = {
    fg = ref("Normal", "fg"),
    bg = ref("StatusLine", "bg"),
  },
}

local function resolve(value)
  if type(value) ~= "table" or not value.group then
    return value
  end

  return M.hl(value.group)[value.attr]
end

local function compile(spec)
  local result = {}

  for attr, value in pairs(spec) do
    result[attr] = resolve(value)
  end

  return result
end

local function inverted(opts)
  return vim.tbl_extend("force", opts, {
    fg = opts.bg,
    bg = opts.fg,
  })
end

function M.set_hl_groups()
  for name, spec in pairs(M.hl_groups) do
    local group = "StatusLine" .. name
    local opts = compile(spec)

    vim.api.nvim_set_hl(0, group, opts)
    vim.api.nvim_set_hl(0, group .. "Inverted", inverted(opts))
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
    require("ui.statusline.name").component(),
    "%=", -- Left/right separator
    "Statusline right-aligned stuff",
  })
end

return M
