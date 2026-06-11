-- Per-spec lz.n matrix: every spec in init.lua is asserted not-loaded before
-- its trigger and loaded (module + runtimepath) after it. Each case runs in
-- a fresh child, so shared triggers (e.g. one :edit firing BufReadPre,
-- BufReadPost and FileType) cannot leak across cases.
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

local function keys(sequence)
  return function(c)
    c.type_keys(sequence)
  end
end

local function edit(fixture)
  return function(c)
    H.edit_fixture(c, fixture)
  end
end

local function esc(c)
  c.type_keys('<Esc>')
end

-- name = spec/packadd dir, mod = lua module the spec's hooks require().
local lazy_specs = {
  {
    name = 'mini.pick',
    mod = 'mini.pick',
    trigger = keys(' f'),
    extra_rtp = { 'mini.extra' },
    cleanup = function(c)
      c.type_keys('<Esc>')
      c.lua([[pcall(function() require('mini.pick').stop() end)]])
    end,
  },
  { name = 'smart-splits.nvim', mod = 'smart-splits', trigger = keys('<A-h>') },
  {
    name = 'nvim-dap',
    mod = 'dap',
    trigger = keys(' Db'),
    extra_rtp = { 'nvim-dap-ui', 'nvim-nio', 'nvim-dap-virtual-text' },
  },
  { name = 'nvim-dap-ui', mod = 'dapui', trigger = keys(' Do') },
  { name = 'mini.surround', mod = 'mini.surround', trigger = keys('sa'), cleanup = esc },
  { name = 'gitsigns.nvim', mod = 'gitsigns', trigger = edit('hello.md') },
  { name = 'nvim-lint', mod = 'lint', trigger = edit('hello.md') },
  {
    name = 'conform.nvim',
    mod = 'conform',
    trigger = function(c)
      c.lua([[
        vim.cmd.edit(vim.fn.tempname() .. '.txt')
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'conform trigger' })
        vim.cmd.write()
      ]])
    end,
  },
  { name = 'ultimate-autopair.nvim', mod = 'ultimate-autopair', trigger = keys('i'), cleanup = esc },
  { name = 'blink.cmp', mod = 'blink.cmp', trigger = keys('i'), cleanup = esc, extra_rtp = { 'mini.icons' } },
  { name = 'lean.nvim', mod = 'lean', trigger = edit('hello.lean'), extra_rtp = { 'plenary.nvim' } },
  { name = 'clangd_extensions.nvim', mod = 'clangd_extensions', trigger = edit('hello.c') },
}

T['lazy specs'] = MiniTest.new_set()
for _, spec in ipairs(lazy_specs) do
  T['lazy specs'][spec.name] = function()
    eq(child.lua_get(('T.loaded(%q)'):format(spec.mod)), false)
    eq(child.lua_get(('T.rtp_has(%q)'):format(spec.name)), false)
    for _, dep in ipairs(spec.extra_rtp or {}) do
      eq(child.lua_get(('T.rtp_has(%q)'):format(dep)), false)
    end

    spec.trigger(child)
    H.wait_until(child, ('T.loaded(%q)'):format(spec.mod))

    eq(child.lua_get(('T.rtp_has(%q)'):format(spec.name)), true)
    for _, dep in ipairs(spec.extra_rtp or {}) do
      eq(child.lua_get(('T.rtp_has(%q)'):format(dep)), true)
    end
    if spec.cleanup then
      spec.cleanup(child)
    end
  end
end

T['eager specs'] = MiniTest.new_set()

T['eager specs']['nothing trigger-less is packadded at startup'] = function()
  -- These ride along with their consumers' load fns (mini.pick / nvim-dap);
  -- an eager spec for any of them is startup cost regression (bench M3).
  for _, name in ipairs { 'mini.extra', 'nvim-nio', 'nvim-dap-virtual-text' } do
    eq(child.lua_get(('T.rtp_has(%q)'):format(name)), false)
  end
end

T['eager specs']['nvim-treesitter is set up at startup'] = function()
  eq(child.lua_get([[T.loaded('nvim-treesitter')]]), true)
  eq(child.lua_get([[T.loaded('nvim-treesitter-textobjects')]]), true)
  eq(child.lua_get([[T.rtp_has('nvim-treesitter-textobjects')]]), true)
end

T['Pick command stub exists before load'] = function()
  eq(child.lua_get([[T.loaded('mini.pick')]]), false)
  eq(child.lua_get([[vim.fn.exists(':Pick')]]), 2)
end

T['blink prebuilt fuzzy library loads'] = function()
  child.type_keys('i')
  H.wait_until(child, [[T.loaded('blink.cmp')]])
  child.type_keys('<Esc>')
  -- Guards the nixpkgs prebuilt libblink_cmp_fuzzy.so against build
  -- regressions; a broken library makes this require fail.
  eq(child.lua_get([[(pcall(require, 'blink.cmp.fuzzy.rust'))]]), true)
end

T['every spec name resolves to a packpath dir'] = function()
  local specs = {
    'mini.extra',
    'mini.pick',
    'smart-splits.nvim',
    'nvim-nio',
    'nvim-dap',
    'nvim-dap-ui',
    'nvim-dap-virtual-text',
    'nvim-treesitter',
    'mini.surround',
    'ultimate-autopair.nvim',
    'conform.nvim',
    'nvim-lint',
    'lean.nvim',
    'blink.cmp',
    'gitsigns.nvim',
    'clangd_extensions.nvim',
  }
  for _, name in ipairs(specs) do
    local pattern = 'pack/*/{start,opt}/' .. name
    local expr = ('#vim.fn.globpath(%q, %q, true, true) > 0'):format(H.packpath, pattern)
    if child.lua_get(expr) ~= true then
      error('spec does not resolve to a packpath dir: ' .. name)
    end
  end
end

T['opt packpath inventory matches the specs'] = function()
  -- Bidirectional lock: every opt plugin is reachable from some spec or
  -- load fn, and nothing unaccounted ships in the closure (this is what
  -- keeps lzn-auto-require-style dead weight out for good).
  local known = {
    -- lz.n specs
    'blink.cmp',
    'clangd_extensions.nvim',
    'conform.nvim',
    'gitsigns.nvim',
    'lean.nvim',
    'mini.extra',
    'mini.pick',
    'mini.surround',
    'nvim-dap',
    'nvim-dap-ui',
    'nvim-dap-virtual-text',
    'nvim-lint',
    'nvim-nio',
    'smart-splits.nvim',
    'ultimate-autopair.nvim',
    -- pulled in by custom load fns / explicit packadd
    'mini.icons',
    'minimal.nvim',
    'nvim-treesitter-textobjects',
    'plenary.nvim',
    -- test harness (referenced by tests/minit.lua)
    'mini.test',
    -- blink.cmp compatibility shim: shipped as a dependency of blink.cmp
    -- in nixpkgs; nothing in init.lua loads it. Removal candidate.
    'blink.compat',
  }
  table.sort(known)

  local expr = ([[
    (function()
      local out = {}
      for _, p in ipairs(vim.fn.globpath(%q, 'pack/poincare/opt/*', true, true)) do
        table.insert(out, vim.fs.basename(p))
      end
      table.sort(out)
      return out
    end)()
  ]]):format(H.packpath)
  eq(child.lua_get(expr), known)
end

return T
