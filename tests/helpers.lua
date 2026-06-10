-- Shared infrastructure for the behavioural suite. Loaded by the parent
-- Neovim process (the wrapped poincare binary running tests/minit.lua); the
-- assertions themselves run in child Neovim processes booted with the exact
-- store paths the parent was built from.
local MiniTest = require('mini.test')

local H = {}

local source = debug.getinfo(1, 'S').source:sub(2)
H.tests_dir = vim.fs.dirname(vim.uv.fs_realpath(source) or source)
H.fixtures_dir = H.tests_dir .. '/fixtures'

-- Binary under test. checks.tests and tests/run.sh point POINCARE_NVIM at
-- the wrapper; v:progpath may resolve to the unwrapped binary, which still
-- works because the child arguments below reconstruct the wrapper flags and
-- the wrapper environment (PATH, NVIM_APPNAME, CODELLDB_PATH) is inherited
-- from the parent process.
H.nvim_bin = vim.env.POINCARE_NVIM or vim.v.progpath

-- The parent booted with `-u <configDir>/init.lua` ($MYVIMRC stays unset
-- for explicit -u); recover the config dir from the runtimepath entry the
-- wrapper prepended — the only entry carrying both init.lua and lsp/.
for _, path in ipairs(vim.opt.runtimepath:get()) do
  if vim.uv.fs_stat(path .. '/init.lua') ~= nil and vim.uv.fs_stat(path .. '/lsp') ~= nil then
    H.config_dir = path
    break
  end
end
assert(H.config_dir ~= nil, 'could not locate the wrapper config dir on the runtimepath')
H.init_path = H.config_dir .. '/init.lua'

for _, path in ipairs(vim.opt.packpath:get()) do
  if vim.uv.fs_stat(path .. '/pack/poincare') ~= nil then
    H.packpath = path
    break
  end
end
assert(H.packpath ~= nil, 'could not locate the wrapper packpath entry')

-- mini.test spawns children as `nvim --clean -n --listen <addr> --headless
-- --cmd 'set lines=24 columns=80' <args>`; later arguments win, so the
-- trailing `-u` re-enables the config that `--clean` disabled.
H.child_args = {
  '--cmd',
  'set packpath^=' .. H.packpath,
  '--cmd',
  'set runtimepath^=' .. H.packpath,
  '--cmd',
  'set runtimepath^=' .. H.config_dir,
  '-u',
  H.init_path,
}

-- Query helpers injected into every fresh child so test files stay
-- declarative. Linters never see this code: it is executed in the child.
local child_prelude = [[
  _G.T = {}

  function T.loaded(mod)
    return package.loaded[mod] ~= nil
  end

  function T.rtp_has(name)
    for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
      if vim.fs.basename(path) == name then
        return true
      end
    end
    return false
  end

  function T.lsp_enabled(name)
    if vim.lsp.is_enabled ~= nil then
      return vim.lsp.is_enabled(name)
    end
    return vim.lsp._enabled_configs[name] ~= nil
  end

  function T.map_desc(lhs, mode)
    local info = vim.fn.maparg(lhs, mode, false, true)
    if type(info) ~= 'table' or info.lhs == nil then
      return nil
    end
    return info.desc
  end

  function T.normalize(lhs)
    return vim.api.nvim_replace_termcodes(lhs, true, true, true)
  end

  function T.buf_map_lhs(modes)
    local out = {}
    for _, mode in ipairs(modes) do
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, mode)) do
        table.insert(out, T.normalize(map.lhs))
      end
    end
    return out
  end
]]

-- Minimal in-process LSP server: enough of the protocol for a real
-- LspAttach, so the buffer-local keymaps can be inspected without an
-- external binary.
local fake_lsp = [[
  _G.__attached = false
  vim.api.nvim_create_autocmd('LspAttach', {
    once = true,
    callback = function()
      _G.__attached = true
    end,
  })
  local function server(dispatchers)
    local closing = false
    return {
      request = function(method, _, handler)
        if method == 'initialize' then
          handler(nil, { capabilities = {} })
        elseif method == 'shutdown' then
          handler(nil, nil)
        end
        return true, 1
      end,
      notify = function()
        return false
      end,
      is_closing = function()
        return closing
      end,
      terminate = function()
        closing = true
        dispatchers.on_exit(0, 15)
      end,
    }
  end
  vim.lsp.start({ name = 'fake-ls', cmd = server, root_dir = vim.uv.cwd() }, { bufnr = 0 })
]]

function H.new_child()
  return MiniTest.new_child_neovim()
end

function H.restart(child)
  child.restart(H.child_args, { nvim_executable = H.nvim_bin, connection_timeout = 15000 })
  child.lua(child_prelude)
end

function H.start_fake_lsp(child)
  child.lua(fake_lsp)
end

-- Poll an expression in the child until it evaluates to `true`.
function H.wait_until(child, expr, timeout_ms)
  timeout_ms = timeout_ms or 15000
  local start = vim.uv.hrtime()
  while (vim.uv.hrtime() - start) / 1e6 < timeout_ms do
    if child.lua_get(expr) == true then
      return
    end
    vim.uv.sleep(20)
  end
  error(('timed out after %dms waiting for: %s'):format(timeout_ms, expr), 2)
end

function H.fixture(name)
  local path = H.fixtures_dir .. '/' .. name
  assert(vim.uv.fs_stat(path) ~= nil, 'missing fixture: ' .. path)
  return path
end

function H.edit_fixture(child, name)
  -- silent!: nvim-lint's BufEnter hook errors loudly when a linter binary
  -- is missing (intentionally absent from the closure); assertions after
  -- the edit catch genuine failures.
  child.cmd('silent! edit ' .. vim.fn.fnameescape(H.fixture(name)))
end

-- Write throwaway executables and prepend them to PATH for the duration of
-- `fn`. Children inherit the parent environment, so a restart inside `fn`
-- sees the shims.
function H.with_path_shims(names, fn)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  for _, name in ipairs(names) do
    local path = dir .. '/' .. name
    vim.fn.writefile({ '#!/bin/sh', 'exit 0' }, path)
    vim.uv.fs_chmod(path, 493) -- 0755
  end
  local saved = vim.env.PATH
  vim.env.PATH = dir .. ':' .. saved
  local ok, err = pcall(fn)
  vim.env.PATH = saved
  if not ok then
    error(err, 0)
  end
end

-- lz.n `keys` trigger registry: the single source of truth for the keymap
-- tests. Lhs are stored concretely (leader is a literal space, set before
-- any spec registers). A keys-spec change in init.lua must update this
-- table; that coupling is the locking property the suite relies on.
H.trigger_keys = {
  ['mini.pick'] = {
    { mode = 'n', lhs = ' f' },
    { mode = 'n', lhs = ' /' },
    { mode = 'n', lhs = ' d' },
    { mode = 'n', lhs = ' e' },
    { mode = 'n', lhs = ' g' },
    { mode = 'n', lhs = ' s' },
    { mode = 'n', lhs = ' S' },
    { mode = 'n', lhs = ' r' },
    { mode = 'n', lhs = ' i' },
    { mode = 'n', lhs = ' T' },
  },
  ['smart-splits.nvim'] = {
    { mode = 'n', lhs = '<A-h>' },
    { mode = 'n', lhs = '<A-j>' },
    { mode = 'n', lhs = '<A-k>' },
    { mode = 'n', lhs = '<A-l>' },
    { mode = 'n', lhs = '<C-h>' },
    { mode = 'n', lhs = '<C-j>' },
    { mode = 'n', lhs = '<C-k>' },
    { mode = 'n', lhs = '<C-l>' },
    { mode = 'n', lhs = '<C-\\>' },
  },
  ['nvim-dap'] = {
    { mode = 'n', lhs = ' Db' },
    { mode = 'n', lhs = ' Dc' },
    { mode = 'n', lhs = ' Ds' },
    { mode = 'n', lhs = ' DS' },
    { mode = 'n', lhs = ' Dr' },
    { mode = 'n', lhs = ' DC' },
    { mode = 'n', lhs = ' DT' },
  },
  ['nvim-dap-ui'] = {
    { mode = 'n', lhs = ' Do' },
    { mode = 'n', lhs = ' Dx' },
    { mode = 'n', lhs = ' Dt' },
  },
  ['clangd_extensions.nvim'] = {
    { mode = 'n', lhs = ' cs' },
    { mode = 'n', lhs = ' cT' },
  },
}

function H.all_trigger_keys()
  local out = {}
  for _, entries in pairs(H.trigger_keys) do
    for _, entry in ipairs(entries) do
      table.insert(out, entry)
    end
  end
  return out
end

return H
