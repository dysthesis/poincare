-- Keymap invariants for the lz.n keys-spec triggers (registry lives in
-- helpers.lua):
--   1. every trigger lhs is mapped with a non-empty *string* desc — a table
--      desc aborts handler registration for the whole plugin (bug 1);
--   2. descs are unique — locks the <leader>e/<leader>g copy-paste class;
--   3. LspAttach buffer-local maps never shadow a global trigger — locks
--      the clangd re-home to <leader>cs/<leader>cT.
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

T['every trigger lhs is mapped with a string desc'] = function()
  for _, entry in ipairs(H.all_trigger_keys()) do
    local desc = child.lua_get(('T.map_desc(%q, %q)'):format(entry.lhs, entry.mode))
    if desc == vim.NIL then
      error(('trigger %q (mode %q) is not mapped'):format(entry.lhs, entry.mode))
    end
    if type(desc) ~= 'string' or desc == '' then
      error(('trigger %q has a non-string or empty desc: %s'):format(entry.lhs, vim.inspect(desc)))
    end
  end
end

T['trigger descs are unique'] = function()
  local seen = {}
  for _, entry in ipairs(H.all_trigger_keys()) do
    local desc = child.lua_get(('T.map_desc(%q, %q)'):format(entry.lhs, entry.mode))
    if type(desc) == 'string' then
      if seen[desc] ~= nil then
        error(('duplicate desc %q on %q and %q'):format(desc, seen[desc], entry.lhs))
      end
      seen[desc] = entry.lhs
    end
  end
end

T['LspAttach buffer-local maps do not shadow triggers'] = function()
  H.start_fake_lsp(child)
  H.wait_until(child, '_G.__attached == true')

  local buf_lhs = child.lua_get([[T.buf_map_lhs({ 'n', 'x', 'i' })]])
  local buf_set = {}
  for _, lhs in ipairs(buf_lhs) do
    buf_set[lhs] = true
  end

  -- The LspAttach side of the historic collision must exist...
  eq(buf_set[' ch'], true)
  eq(buf_set[' ct'], true)

  -- ...and no global trigger may be shadowed by it.
  for _, entry in ipairs(H.all_trigger_keys()) do
    local normalized = child.lua_get(('T.normalize(%q)'):format(entry.lhs))
    if buf_set[normalized] then
      error(('LspAttach buffer-local map shadows lz.n trigger %q'):format(entry.lhs))
    end
  end
end

return T
