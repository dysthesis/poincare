local MiniTest = require("mini.test")
local root = vim.fs.dirname(
  vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))
)
local child = MiniTest.new_child_neovim()
local eq = MiniTest.expect.equality
local directory
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      directory =
        assert(vim.uv.fs_mkdtemp("/tmp/poincare-lua-libraries-XXXXXX"))
      child.restart()
      child.lua(
        [[
        local root, directory = ...
        vim.env.HOME = directory
        vim.env.XDG_CONFIG_HOME = directory .. "/config"
        vim.env.XDG_CACHE_HOME = directory .. "/cache"
        vim.env.XDG_STATE_HOME = directory .. "/state"
        vim.env.NVIM_APPNAME = "poincare-library-test"
        vim.env.VIMRUNTIME = directory .. "/runtime"
        vim.env.POINCARE_TEST_LIBRARY = directory .. "/project-library"
        local function write(path, lines)
          vim.fn.mkdir(vim.fs.dirname(path), "p")
          assert(vim.fn.writefile(lines, path) == 0)
        end
        local source = {
          "local function control() return 1 end",
          "local control_use = control()",
          "local runtime_use = runtime_only()",
          "local project_use = project_only()",
          "return control_use, runtime_use, project_use",
        }
        _G.LibraryTest = { write = write, source = source }
        LibraryTest.config = vim.fn.stdpath("config")
        assert(vim.startswith(LibraryTest.config, directory .. "/"), "config isolation failed")
        LibraryTest.project = directory .. "/ordinary"
        LibraryTest.plain = directory .. "/plain"
        LibraryTest.runtime = vim.env.VIMRUNTIME .. "/runtime-api.lua"
        LibraryTest.extra = vim.env.POINCARE_TEST_LIBRARY .. "/project-api.lua"
        write(LibraryTest.runtime, { "function runtime_only() return 2 end" })
        write(LibraryTest.extra, { "function project_only() return 3 end" })
        write(LibraryTest.config .. "/init.lua", source)
        write(LibraryTest.project .. "/main.lua", source)
        write(LibraryTest.project .. "/.luarc.json", { "{}" })
        write(LibraryTest.plain .. "/main.lua", source)
        vim.lsp.config["lua-language-server"] = dofile(root .. "/src/lsp/lua-language-server.lua")
        vim.lsp.enable("lua-language-server")
      ]],
        { root, directory }
      )
    end,
    post_case = function()
      if child.is_running() then
        child.lua([[
          vim.lsp.stop_client(vim.lsp.get_clients({ _uninitialized = true }), true)
          vim.wait(2000, function()
            return #vim.lsp.get_clients({ _uninitialized = true }) == 0
          end, 10)
        ]])
        child.stop()
      end
      vim.fn.delete(directory, "rf")
    end,
  },
})

local function open(path, unsaved)
  return child.lua(
    [[
    local path, unsaved = ...
    vim.cmd.edit(vim.fn.fnameescape(path))
    if unsaved then
      vim.api.nvim_buf_set_lines(0, 0, -1, false, LibraryTest.source)
    end
    vim.bo.filetype = "lua"
    local client
    assert(vim.wait(10000, function()
      client = vim.lsp.get_clients({ bufnr = 0, name = "lua-language-server" })[1]
      return client and client.initialized
    end, 10), "LuaLS did not initialize and attach")
    return client.id
  ]],
    { path, unsaved or false }
  )
end

local function definition(line, word)
  return child.lua(
    [[
    local line, word = ...
    local client = assert(vim.lsp.get_clients({ bufnr = 0, name = "lua-language-server" })[1])
    local text = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1]
    local position = assert(text:find(word, 1, true)) - 1
    local response, err = client:request_sync("textDocument/definition", {
      textDocument = { uri = vim.uri_from_bufnr(0) },
      position = { line = line - 1, character = position },
    }, 10000, 0)
    assert(response and not response.err, vim.inspect(err or response))
    local locations = response.result
    if not locations or locations == vim.NIL then return {} end
    local location = locations.uri and locations or locations[1]
    if not location then return {} end
    local uri = location.targetUri or location.uri
    local range = location.targetSelectionRange or location.range
    return { path = vim.uv.fs_realpath(vim.uri_to_fname(uri)), line = range.start.line }
  ]],
    { line, word }
  )
end

local function path(field)
  return child.lua_get("LibraryTest." .. field)
end

local function control(file)
  eq(definition(2, "control()"), { path = vim.uv.fs_realpath(file), line = 0 })
end

T["ordinary and config projects keep different library visibility in one editor"] = function()
  local config = path("config") .. "/init.lua"
  local ordinary = path("project") .. "/main.lua"
  local config_client = open(config)
  control(config)
  eq(definition(3, "runtime_only"), { path = path("runtime"), line = 0 })
  local ordinary_client = open(ordinary)
  assert(ordinary_client ~= config_client, "unrelated roots reused one client")
  control(ordinary)
  eq(definition(3, "runtime_only"), {})
  eq(open(config), config_client)
  eq(definition(3, "runtime_only"), { path = path("runtime"), line = 0 })
end

T["canonical config roots include inward links but not outward links or sibling prefixes"] = function()
  child.lua([[
    local actual = vim.env.HOME .. "/actual-config"
    assert(vim.uv.fs_rename(LibraryTest.config, actual))
    assert(vim.uv.fs_symlink(actual, LibraryTest.config))
    assert(vim.uv.fs_symlink(actual .. "/init.lua", LibraryTest.plain .. "/inward.lua"))
    assert(vim.uv.fs_symlink(LibraryTest.plain .. "/main.lua", actual .. "/outward.lua"))
    LibraryTest.sibling = LibraryTest.config .. "-sibling/init.lua"
    LibraryTest.write(LibraryTest.sibling, LibraryTest.source)
  ]])
  local inward = path("plain") .. "/inward.lua"
  open(inward)
  control(inward)
  eq(definition(3, "runtime_only"), { path = path("runtime"), line = 0 })
  local outward = path("config") .. "/outward.lua"
  open(outward)
  control(outward)
  eq(definition(3, "runtime_only"), {})
  local sibling = path("sibling")
  open(sibling)
  control(sibling)
  eq(definition(3, "runtime_only"), {})
end

T["unsaved files below new config directories retain runtime definitions"] = function()
  local file = path("config") .. "/not-created/yet/module.lua"
  open(file, true)
  eq(definition(3, "runtime_only"), { path = path("runtime"), line = 0 })
  eq(vim.uv.fs_stat(vim.fs.dirname(file)), nil)
end

T["literal environment-variable text does not opt unrelated directories in"] = function()
  child.lua([[
    vim.env.PART = "expanded"
    vim.env.XDG_CONFIG_HOME = vim.env.HOME .. "/$PART"
    LibraryTest.config = vim.fn.stdpath("config")
    LibraryTest.write(LibraryTest.config .. "/init.lua", LibraryTest.source)
    LibraryTest.lookalike = vim.env.HOME .. "/expanded/" .. vim.env.NVIM_APPNAME .. "/main.lua"
    LibraryTest.write(LibraryTest.lookalike, LibraryTest.source)
  ]])
  local unrelated = path("lookalike")
  open(unrelated)
  control(unrelated)
  eq(definition(3, "runtime_only"), {})
  local config = path("config") .. "/init.lua"
  open(config)
  control(config)
  eq(definition(3, "runtime_only"), { path = path("runtime"), line = 0 })
end

T["an explicit empty client library disables config runtime support"] = function()
  child.lua(
    "vim.lsp.config['lua-language-server'].settings.Lua.workspace.library = {}"
  )
  local file = path("config") .. "/init.lua"
  open(file)
  control(file)
  eq(definition(3, "runtime_only"), {})
end

T["an explicit client library replaces automatic config libraries"] = function()
  child.lua(
    "vim.lsp.config['lua-language-server'].settings.Lua.workspace.library = { vim.env.POINCARE_TEST_LIBRARY }"
  )
  local file = path("config") .. "/init.lua"
  open(file)
  control(file)
  eq(definition(3, "runtime_only"), {})
  eq(definition(4, "project_only"), { path = path("extra"), line = 0 })
end

T["project JSONC can opt into the runtime without a global client library"] = function()
  child.lua([[
    assert(vim.fn.delete(LibraryTest.project .. "/.luarc.json") == 0)
    LibraryTest.write(LibraryTest.project .. "/.luarc.jsonc", {
      "{ // Explicit project opt-in",
      '  "workspace.library": ["${env:VIMRUNTIME}"]',
      "}",
    })
  ]])
  local file = path("project") .. "/main.lua"
  open(file)
  control(file)
  eq(definition(3, "runtime_only"), { path = path("runtime"), line = 0 })
end

T["a separately rooted config descendant can opt into its own library"] = function()
  child.lua([[
    LibraryTest.nested = LibraryTest.config .. "/nested"
    LibraryTest.write(LibraryTest.nested .. "/main.lua", LibraryTest.source)
    LibraryTest.write(LibraryTest.nested .. "/.luarc.json", {
      '{"workspace.library":["${env:POINCARE_TEST_LIBRARY}"]}',
    })
  ]])
  local file = path("nested") .. "/main.lua"
  open(file)
  control(file)
  eq(definition(3, "runtime_only"), {})
  eq(definition(4, "project_only"), { path = path("extra"), line = 0 })
end

T["synchronous roots start the real server before file opening returns"] = function()
  local file = path("project") .. "/main.lua"
  child.lua([[
    local config = vim.lsp.config["lua-language-server"]
    local resolve = config.root_dir
    local before_init = config.before_init
    local resolved = false
    local started_after_resolution = false
    config.root_dir = function(bufnr, on_dir)
      resolved = false
      resolve(bufnr, on_dir)
      resolved = true
    end
    config.before_init = function(params, client_config)
      started_after_resolution = resolved
      before_init(params, client_config)
    end
    vim.cmd.edit(vim.fn.fnameescape(LibraryTest.project .. "/main.lua"))
    vim.bo.filetype = "lua"
    local clients = vim.lsp.get_clients({ bufnr = 0, _uninitialized = true })
    assert(#clients == 1, "resolved root unnecessarily deferred server startup")
    assert(started_after_resolution, "server started reentrantly inside root resolution")
    assert(clients[1].config.root_dir == LibraryTest.project, "resolved root was not used")
  ]])
  open(file)
  control(file)
end

T["asynchronous roots can resolve from a fast event and still attach"] = function()
  child.lua([[
    local config = vim.lsp.config["lua-language-server"]
    local before_init = config.before_init
    config.root_dir = function(_, on_dir)
      local timer = assert(vim.uv.new_timer())
      timer:start(0, 0, function()
        timer:close()
        LibraryTest.root_fast_event = vim.in_fast_event()
        on_dir(LibraryTest.project)
      end)
    end
    config.before_init = function(params, client_config)
      LibraryTest.startup_fast_event = vim.in_fast_event()
      before_init(params, client_config)
    end
  ]])
  local file = path("project") .. "/main.lua"
  open(file)
  eq(child.lua_get("LibraryTest.root_fast_event"), true)
  eq(child.lua_get("LibraryTest.startup_fast_event"), false)
  control(file)
  eq(definition(3, "runtime_only"), {})
end

T["roots that omit the callback do not activate the real server"] = function()
  child.lua([[
    local calls = 0
    vim.lsp.config["lua-language-server"].root_dir = function()
      calls = calls + 1
      return LibraryTest.project
    end
    vim.cmd.edit(vim.fn.fnameescape(LibraryTest.project .. "/main.lua"))
    vim.bo.filetype = "lua"
    assert(calls > 0, "fixture did not invoke the root resolver")
    local settled = false
    vim.schedule(function() settled = true end)
    assert(vim.wait(1000, function() return settled end, 10), "scheduled startup did not settle")
    local clients = vim.lsp.get_clients({ name = "lua-language-server", _uninitialized = true })
    assert(#clients == 0, "root resolver activated LuaLS without calling on_dir")
  ]])
end

return T
