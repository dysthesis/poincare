local MiniTest = require('mini.test')
local H = require('helpers')

local child = H.new_child()

local T = MiniTest.new_set {
  hooks = {
    pre_case = function()
      H.restart(child)
    end,
    post_once = child.stop,
  },
}

local eq = MiniTest.expect.equality

T['headless boot is silent and exits zero'] = function()
  local cmd = { H.nvim_bin }
  vim.list_extend(cmd, H.child_args)
  vim.list_extend(cmd, { '--headless', '+qa' })
  local res = vim.system(cmd, { text = true }):wait()
  eq(res.stderr, '')
  eq(res.code, 0)
end

T['core options'] = function()
  eq(child.lua_get('vim.o.shiftwidth'), 2)
  eq(child.lua_get('vim.o.tabstop'), 2)
  eq(child.lua_get('vim.o.softtabstop'), 2)
  eq(child.lua_get('vim.o.laststatus'), 3)
  eq(child.lua_get('vim.o.termguicolors'), true)
end

T['leader keys'] = function()
  eq(child.lua_get('vim.g.mapleader'), ' ')
  eq(child.lua_get('vim.g.maplocalleader'), '\r')
end

T['colourscheme is minimal'] = function()
  eq(child.lua_get('vim.g.colors_name'), 'minimal')
end

T['statusline shows the mode abbreviation'] = function()
  eq(child.lua_get([[vim.o.statusline:find('mode_abbr', 1, true) ~= nil]]), true)
  eq(child.lua_get('vim.mode_abbr()'), 'NOR')
end

T['command-line typo abbreviations'] = function()
  local typos = {
    ['W!'] = 'w!',
    ['Q!'] = 'q!',
    ['Qall!'] = 'qall!',
    ['Wq'] = 'wq',
    ['Wa'] = 'wa',
    ['wQ'] = 'wq',
    ['WQ'] = 'wq',
    ['W'] = 'w',
    ['Q'] = 'q',
  }
  for from, to in pairs(typos) do
    eq(child.lua_get(([[vim.fn.maparg(%q, 'c', true, true).rhs]]):format(from)), to)
  end
end

return T
