---@diagnostic disable: undefined-global, deprecated
local M = {}
local state = rawget(_G, "poincare_perf_state") or { events = {}, stack = {}, next_id = 1 }
_G.poincare_perf_state = state
local original_require = state.original_require

local function pack(...)
  return { n = select("#", ...), ... }
end

local function error_value(ok, value)
  if ok then return vim.NIL end
  return tostring(value)
end

local function snapshot()
  local result = { lua_kib = collectgarbage("count") }
  if vim.uv and vim.uv.getrusage then
    local ok, usage = pcall(vim.uv.getrusage)
    if ok then result.rusage = usage end
  end
  return result
end

local function begin_event(name, kind, metadata)
  local event = {
    id = state.next_id,
    parent_id = state.stack[#state.stack],
    name = name,
    kind = kind,
    begin_ns = vim.uv.hrtime(),
    before = snapshot(),
  }
  state.next_id = state.next_id + 1
  if metadata then for key, value in pairs(metadata) do event[key] = value end end
  state.events[#state.events + 1] = event
  state.stack[#state.stack + 1] = event.id
  return event
end

local function end_event(event, ok, err)
  event.end_ns = vim.uv.hrtime()
  event.duration_ns = event.end_ns - event.begin_ns
  event.ok = ok
  event.error = error_value(ok, err)
  event.after = snapshot()
  assert(table.remove(state.stack) == event.id, "performance span stack corrupted")
end

local function invoke(event, fn, ...)
  local arguments = pack(...)
  local result = pack(xpcall(function()
    return fn(unpack(arguments, 1, arguments.n))
  end, debug.traceback))
  local ok = result[1]
  end_event(event, ok, result[2])
  if not ok then error(result[2], 0) end
  return unpack(result, 2, result.n)
end

function M.preinit()
  state.startup = begin_event("startup", "startup")
  original_require = require
  state.original_require = original_require
  state.profile = true
  _G.require = function(module)
    local cached = package.loaded[module] ~= nil and package.loaded[module] ~= false
    local info = debug.getinfo(2, "Sl") or {}
    local event = begin_event(module, "require", {
      module = module,
      cached = cached,
      source = info.short_src,
      source_line = info.currentline,
    })
    return invoke(event, original_require, module)
  end
end

local function write_result(result)
  local encoded = vim.json.encode(result)
  local handle, err = io.open(assert(os.getenv("POINCARE_PERF_OUTPUT")), "wb")
  assert(handle, err)
  handle:write(encoded)
  handle:close()
end

function M.run()
  if state.startup then end_event(state.startup, vim.v.errmsg == "", vim.v.errmsg) end
  local result = {
    protocol = "poincare-perf-trace/v1",
    runtime = {
      version = vim.version(),
      jit = jit and { version = jit.version, os = jit.os, arch = jit.arch, status = pack(jit.status()) } or vim.NIL,
    },
    startup_error = vim.v.errmsg ~= "" and vim.v.errmsg or vim.NIL,
    events = state.events,
    steps = {},
  }
  local config_file = assert(io.open(assert(os.getenv("POINCARE_PERF_CONFIG")), "rb"))
  local config = vim.json.decode(config_file:read("*a"))
  config_file:close()
  local bench = {}
  function bench.span(name, fn, ...)
    local event = state.profile and begin_event(name, "span") or nil
    if event then return invoke(event, fn, ...) end
    return fn(...)
  end
  local workload = state.profile and begin_event("workload", "workload") or nil
  local function execute(code, label)
    local fn, compile_error = loadstring(code, "@bench/" .. label)
    if not fn then error(compile_error) end
    return fn()(bench)
  end
  local ok, failure = xpcall(function()
    if config.setup then execute(config.setup, "setup") end
    for _, step in ipairs(config.steps) do
      local event = state.profile and begin_event(step.name, "step") or nil
      local step_ok, step_error = xpcall(function()
        return execute(step.lua, step.name)
      end, debug.traceback)
      if event then end_event(event, step_ok, step_error) end
      result.steps[#result.steps + 1] = { name = step.name, ok = step_ok, error = error_value(step_ok, step_error) }
      if not step_ok then error(step_error, 0) end
    end
  end, debug.traceback)
  if workload then end_event(workload, ok, failure) end
  if original_require then _G.require = original_require end
  result.ok = ok and result.startup_error == vim.NIL
  result.error = error_value(ok, failure)
  result.finished_ns = vim.uv.hrtime()
  write_result(result)
  vim.cmd("qa!")
end

return M
