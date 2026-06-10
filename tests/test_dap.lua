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

-- Map of dapui element buffers (name -> bufnr); a second dapui.setup()
-- deletes and recreates them, so stable bufnrs prove setup ran once.
local dapui_buffers = [[
  (function()
    local out = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local tail = vim.fs.basename(vim.api.nvim_buf_get_name(buf))
      if tail:find('^DAP ') or tail:find('dap%-repl') then
        out[tail] = buf
      end
    end
    return out
  end)()
]]

T['dapui-first wires the full dap stack (locks bug 5)'] = function()
  child.type_keys(' Do')
  H.wait_until(child, [[package.loaded['dapui'] ~= nil]])

  eq(child.lua_get([[require('dap').adapters.codelldb ~= nil]]), true)
  eq(child.lua_get([[require('dap').configurations.rust ~= nil]]), true)
  eq(child.lua_get([[require('dap').configurations.c ~= nil]]), true)
  eq(child.lua_get([[require('dap').configurations.cpp ~= nil]]), true)

  for _, listener in ipairs { 'attach', 'launch', 'event_terminated', 'event_exited' } do
    local expr = ([[type(require('dap').listeners.before[%q].dapui_config)]]):format(listener)
    eq(child.lua_get(expr), 'function')
  end
end

T['dap signs are defined'] = function()
  child.type_keys(' Db')
  H.wait_until(child, [[package.loaded['dap'] ~= nil]])
  for _, sign in ipairs { 'DapBreakpoint', 'DapBreakpointCondition', 'DapLogPoint' } do
    eq(child.lua_get(([[#vim.fn.sign_getdefined(%q) > 0]]):format(sign)), true)
  end
end

T['CODELLDB_PATH is executable'] = function()
  eq(child.lua_get([[vim.fn.executable(vim.env.CODELLDB_PATH or '') == 1]]), true)
end

T['dap-first then dapui does not re-run setup'] = function()
  -- <leader>Db loads through the nvim-dap spec (same lz.n path as
  -- <leader>Dc, without continue()'s prompts); dap's after() runs the one
  -- and only dapui.setup. dapui creates its element buffers on first open,
  -- so open through the dapui spec, then close and reopen: under the old
  -- double-setup wiring every reopen recreated the buffers (E565 class).
  child.type_keys(' Db')
  H.wait_until(child, [[package.loaded['dap'] ~= nil]])
  eq(child.lua_get([[package.loaded['dapui'] ~= nil]]), true)

  child.type_keys(' Dt')
  H.wait_until(child, [[#vim.api.nvim_list_wins() > 1]])
  local before = child.lua_get(dapui_buffers)
  if next(before) == nil then
    error('no dapui element buffers exist after open')
  end

  child.type_keys(' Dx')
  H.wait_until(child, [[#vim.api.nvim_list_wins() == 1]])
  child.type_keys(' Do')
  H.wait_until(child, [[#vim.api.nvim_list_wins() > 1]])

  local after = child.lua_get(dapui_buffers)
  for name, bufnr in pairs(before) do
    if after[name] ~= bufnr then
      error(('dapui element buffer %q was recreated (%s -> %s)'):format(name, bufnr, tostring(after[name])))
    end
  end
  eq(child.lua_get('vim.v.errmsg'), '')
end

return T
