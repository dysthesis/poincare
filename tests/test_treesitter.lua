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

local fixtures = {
  c = 'hello.c',
  go = 'hello.go',
  just = 'justfile',
  lean = 'hello.lean',
  lua = 'hello.lua',
  markdown = 'hello.md',
  nix = 'hello.nix',
  python = 'hello.py',
  rust = 'hello.rs',
  zig = 'hello.zig',
}

T['grammars'] = MiniTest.new_set()
for lang, fixture in pairs(fixtures) do
  T['grammars'][lang] = function()
    eq(child.lua_get(([[#vim.api.nvim_get_runtime_file('parser/%s.*', true) > 0]]):format(lang)), true)
    eq(child.lua_get(([[vim.treesitter.query.get(%q, 'highlights') ~= nil]]):format(lang)), true)

    H.edit_fixture(child, fixture)
    eq(child.lua_get(([[(pcall(vim.treesitter.start, 0, %q))]]):format(lang)), true)
    eq(child.lua_get([[vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil]]), true)
  end
end

T['grammar dirs ship in the packpath'] = function()
  -- nixpkgs grammars land as nvim-treesitter-grammar-<lang> in start; lean
  -- comes from the pinned nvim-treesitter-lean runtime instead.
  for lang in pairs(fixtures) do
    local dir = lang == 'lean' and 'nvim-treesitter-lean' or ('nvim-treesitter-grammar-' .. lang)
    local expr = ('#vim.fn.globpath(%q, %q, true, true) > 0'):format(H.packpath, 'pack/*/start/' .. dir)
    if child.lua_get(expr) ~= true then
      error('grammar dir missing from packpath: ' .. dir)
    end
  end
end

T['minimal.nvim after/queries are on the runtimepath'] = function()
  -- Locks bug 4: the colourscheme used to be found in pack opt without a
  -- packadd, so its after/queries never reached the runtimepath. lean is
  -- deliberately absent: its after-query is stripped in the plugin
  -- derivation (incompatible with the pinned tree-sitter-lean grammar).
  for _, lang in ipairs { 'rust', 'c', 'nix', 'python', 'zig' } do
    local expr = ([[#vim.api.nvim_get_runtime_file('after/queries/%s/highlights.scm', true) > 0]]):format(lang)
    if child.lua_get(expr) ~= true then
      error('minimal.nvim after/queries missing for ' .. lang)
    end
  end
end

return T
