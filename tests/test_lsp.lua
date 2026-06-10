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

T['every lsp/*.lua returns a table with a cmd'] = function()
  -- Configs come from the wrapper's config dir, i.e. the same snapshot the
  -- binary under test resolves at runtime. filetypes is deliberately not
  -- required: nil legally means "all filetypes".
  local files = vim.fn.globpath(H.config_dir .. '/lsp', '*.lua', true, true)
  if #files == 0 then
    error('no lsp configs found under ' .. H.config_dir)
  end
  for _, file in ipairs(files) do
    local name = vim.fn.fnamemodify(file, ':t:r')
    local config = dofile(file)
    if type(config) ~= 'table' then
      error(('lsp/%s.lua does not return a table'):format(name))
    end
    local cmd = config.cmd
    if type(cmd) ~= 'table' and type(cmd) ~= 'function' then
      error(('lsp/%s.lua has no usable cmd (got %s)'):format(name, type(cmd)))
    end
    if type(cmd) == 'table' and type(cmd[1]) ~= 'string' then
      error(('lsp/%s.lua cmd[1] is not a string'):format(name))
    end
  end
end

T['ty config can start and is scoped to python'] = function()
  -- Locks bug 2: without cmd the config could be enabled but never start;
  -- without filetypes it would attach to every buffer.
  eq(child.lua_get('vim.lsp.config.ty.cmd'), { 'ty', 'server' })
  eq(child.lua_get('vim.lsp.config.ty.filetypes'), { 'python' })
end

T['enable gate targets the resolved cmd[1]'] = function()
  -- Locks bug 7: basedpyright's binary is basedpyright-langserver. With
  -- only that shim on PATH the old name-based gate stays red. The hermetic
  -- flake check guarantees no real basedpyright is reachable.
  H.with_path_shims({ 'basedpyright-langserver' }, function()
    H.restart(child)
    eq(child.lua_get([[T.lsp_enabled('basedpyright')]]), true)
  end)
end

T['nil takes precedence over nixd'] = function()
  H.with_path_shims({ 'nil' }, function()
    H.restart(child)
    eq(child.lua_get([[T.lsp_enabled('nil')]]), true)
    -- The pair loop breaks after nil, regardless of a nixd binary.
    eq(child.lua_get([[T.lsp_enabled('nixd')]]), false)
  end)
end

T['nixd is enabled only when nil is absent'] = function()
  H.with_path_shims({ 'nixd' }, function()
    H.restart(child)
    -- Outside the sandbox a real `nil` may sit on PATH; the expectation
    -- tracks that so the precedence rule is locked in both environments.
    local has_nil = child.lua_get([[vim.fn.executable('nil') == 1]])
    eq(child.lua_get([[T.lsp_enabled('nixd')]]), not has_nil)
  end)
end

T['lua-language-server attaches on the fixture project'] = function()
  if child.lua_get([[vim.fn.executable('lua-language-server') == 1]]) ~= true then
    MiniTest.skip('lua-language-server is not on PATH')
  end

  -- silent!: nvim-lint's BufEnter hook errors loudly when the lua linter
  -- binary is absent (it is intentionally not in the closure).
  child.cmd('silent! edit ' .. vim.fn.fnameescape(H.fixture('lua-project/main.lua')))
  H.wait_until(child, [[#vim.lsp.get_clients({ bufnr = 0 }) > 0]], 30000)
  eq(child.lua_get([[vim.lsp.get_clients({ bufnr = 0 })[1].name]]), 'lua-language-server')

  -- LspAttach wired the buffer-local maps.
  local buf_lhs = child.lua_get([[T.buf_map_lhs({ 'n' })]])
  local buf_set = {}
  for _, lhs in ipairs(buf_lhs) do
    buf_set[lhs] = true
  end
  for _, lhs in ipairs { 'K', 'gd', 'gq' } do
    if not buf_set[lhs] then
      error(('LspAttach did not map %q buffer-locally'):format(lhs))
    end
  end
end

return T
