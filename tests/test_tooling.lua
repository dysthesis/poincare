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

T['every conform formatter resolves in the registry'] = function()
  -- Locks bug 3 ('go/fmt' was not a conform formatter): unknown names have
  -- no formatter config. Availability is not asserted — the binaries are
  -- intentionally absent from the closure.
  child.lua([[require('lz.n').trigger_load('conform.nvim')]])
  local by_ft = child.lua_get([[require('conform').formatters_by_ft]])
  if next(by_ft) == nil then
    error('formatters_by_ft is empty')
  end
  for ft, names in pairs(by_ft) do
    for _, name in ipairs(names) do
      local expr = ([[require('conform').get_formatter_config(%q) ~= nil]]):format(name)
      if child.lua_get(expr) ~= true then
        error(('formatter %q (ft %s) does not resolve in conform'):format(name, ft))
      end
    end
  end
end

T['every nvim-lint linter resolves'] = function()
  child.lua([[require('lz.n').trigger_load('nvim-lint')]])
  local by_ft = child.lua_get([[require('lint').linters_by_ft]])
  if next(by_ft) == nil then
    error('linters_by_ft is empty')
  end
  for ft, names in pairs(by_ft) do
    for _, name in ipairs(names) do
      local expr = ([[(pcall(function()
        assert(require('lint').linters[%q] ~= nil)
      end))]]):format(name)
      if child.lua_get(expr) ~= true then
        error(('linter %q (ft %s) does not resolve in nvim-lint'):format(name, ft))
      end
    end
  end
end

T['zlint parser maps gh output to diagnostics'] = function()
  child.lua([[require('lz.n').trigger_load('nvim-lint')]])
  -- silent!: the BufEnter lint hook errors on the absent zlint binary.
  child.lua([[vim.cmd('silent! edit foo.zig')]])
  local items = child.lua_get([[
    (function()
      local bufnr = vim.api.nvim_get_current_buf()
      local output = table.concat({
        '::error file=foo.zig,line=3,col=7,title=bad thing',
        '::warning file=foo.zig,line=1,col=2,title=meh',
        '::error file=other.zig,line=9,col=9,title=ignored',
        'random noise',
      }, '\n')
      return require('lint').linters.zlint.parser(output, bufnr)
    end)()
  ]])
  eq(#items, 2)

  eq(items[1].lnum, 2)
  eq(items[1].col, 6)
  eq(items[1].message, 'bad thing')
  eq(items[1].severity, child.lua_get('vim.diagnostic.severity.ERROR'))

  eq(items[2].lnum, 0)
  eq(items[2].col, 1)
  eq(items[2].message, 'meh')
  eq(items[2].severity, child.lua_get('vim.diagnostic.severity.WARN'))
end

return T
