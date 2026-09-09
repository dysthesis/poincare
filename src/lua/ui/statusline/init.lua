-- M.based on https://jacobnscott.com/posts/nvim-statusline/
local M = {}

function M.hl(group)
  return vim.api.nvim_get_hl(0, {
    name = group,
    link = false,
    create = false,
  })
end

local mode = require("ui.statusline.mode")
local name_component = require("ui.statusline.name")
local ft = require("ui.statusline.ft")
local pos = require("ui.statusline.pos")

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

M.left_components = {
  mode,
  name_component,
}

M.right_components = {
  ft,
  pos,
}

function M.set_section_hl(section)
  for _, component in ipairs(section) do
    if component.hl_groups then
      for name, spec in pairs(component.hl_groups) do
        local group = "StatusLine" .. name
        local opts = compile(spec)

        vim.api.nvim_set_hl(0, group, opts)
      end
    end
  end
end

function M.set_hl_groups()
  M.set_section_hl(M.left_components)
  M.set_section_hl(M.right_components)
end

M.set_hl_groups()

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("my_statusline", { clear = true }),
  desc = "Re-apply statusline highlights on colorscheme change",
  callback = M.set_hl_groups,
})

M.sep = " "

function M.push_section(modeline, section)
  for idx, component in ipairs(section) do
    if idx ~= 1 then
      table.insert(modeline, M.sep)
    end

    table.insert(modeline, component.component())
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
