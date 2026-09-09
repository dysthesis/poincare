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
    fg = ref("LineNr", "fg"),
    bg = ref("StatusLine", "bg"),
    bold = true,
  },

  Name = {
    fg = ref("Normal", "fg"),
    bg = ref("StatusLine", "bg"),
  },

  FtIcon = {
    fg = ref("LineNr", "fg"),
    bg = ref("StatusLine", "bg"),
  },

  Ft = {
    fg = ref("Normal", "fg"),
    bg = ref("StatusLine", "bg"),
  },

  PosIcon = {
    fg = ref("LineNr", "fg"),
    bg = ref("StatusLine", "bg"),
  },

  Pos = {
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

M.left_components = {
  "mode",
  "name",
}

M.right_components = {
  "ft",
  "pos",
}

M.sep = " "

function M.push_section(modeline, section)
  for idx, component in ipairs(section) do
    if idx ~= 1 then
      table.insert(modeline, M.sep)
    end

    table.insert(modeline, require("ui.statusline." .. component).component())
  end
end

function M.render()
  local active = vim.fn.win_getid()
  local status = tonumber(vim.g.actual_curwin)

  if status ~= active then
    return "Statusline for inactive windows"
  end

  local modeline = {}

  M.push_section(modeline, M.left_components)
  table.insert(modeline, "%=")
  M.push_section(modeline, M.right_components)

  return table.concat(modeline)
end

return M
