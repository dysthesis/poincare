-- bench/ledger.lua — per-plugin load-cost ledger (P4/B2).
--
-- Inject before init.lua: nvim --cmd 'luafile bench/ledger.lua' ...
-- lz.n lives in pack/*/start, which is already requirable at --cmd time
-- (verified empirically), so the wrap is in place before any spec loads.
--
-- Instrumentation point is require('lz.n.loader').load — the only choke
-- point that sees the `before` hook, the load implementation (packadd or a
-- custom `load` fn) AND the `after` hook, for eager and deferred plugins
-- alike. A bare packadd patch would miss the after() hooks, which hold the
-- expensive work (dap/dapui/conform setup).
--
-- Output: JSON written to $BENCH_OUT on VimLeavePre:
--   events[]       {name, ms, since_start_ms, depth}; depth>0 means the
--                  load was triggered inside another load (trigger_load
--                  from a before/after hook) and its time is also contained
--                  in the parent's ms.
--   since_start_ms is relative to this file's execution (pre-init.lua),
--                  not to process exec — close enough for ordering.
--   scenario       {name, ms} if a bench/scenarios/*.lua file ran.
--   rss_post_boot  resident set bytes after startup loads, before scenario
--                  work: sampled at VimEnter interactively, or at scenario
--                  start (scenarios quit inside +cmd, before VimEnter).
--   rss_exit       resident set bytes at VimLeavePre (M8).

local uv = vim.uv
local t0 = uv.hrtime()
local events = {}
local depth = 0
local rss_post_boot = nil

local ok, loader = pcall(require, 'lz.n.loader')
if not ok then
  vim.api.nvim_echo({ { 'bench/ledger.lua: lz.n.loader not requirable, ledger disabled', 'ErrorMsg' } }, true, {})
  return
end

local function names_of(plugins)
  if type(plugins) == 'string' then
    return plugins
  end
  if plugins.name then
    return plugins.name
  end
  local acc = {}
  for _, plugin in pairs(plugins) do
    acc[#acc + 1] = type(plugin) == 'string' and plugin or (plugin.name or '?')
  end
  table.sort(acc)
  return table.concat(acc, ',')
end

local orig_load = loader.load
loader.load = function(plugins, lookup)
  local name = names_of(plugins)
  depth = depth + 1
  local started = uv.hrtime()
  local results = { pcall(orig_load, plugins, lookup) }
  local finished = uv.hrtime()
  depth = depth - 1
  events[#events + 1] = {
    name = name,
    ms = (finished - started) / 1e6,
    since_start_ms = (started - t0) / 1e6,
    depth = depth,
  }
  if not results[1] then
    error(results[2], 0)
  end
  return unpack(results, 2)
end

vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    -- no vim.schedule: +cmd args (the scenario) and qa! run before the
    -- schedule queue drains, so a deferred read never happens
    rss_post_boot = uv.resident_set_memory()
  end,
})

vim.api.nvim_create_autocmd('VimLeavePre', {
  once = true,
  callback = function()
    local out = vim.env.BENCH_OUT
    if not out or out == '' then
      return
    end
    local payload = {
      schema = 'poincare-ledger-v1',
      -- set by bench/scenarios/_run.lua (separate chunk, hence globals)
      -- selene: allow(global_usage)
      scenario = _G.BENCH_SCENARIO,
      -- selene: allow(global_usage)
      rss_post_boot = _G.BENCH_RSS_POST_BOOT or rss_post_boot,
      rss_exit = uv.resident_set_memory(),
      events = events,
    }
    local f = io.open(out, 'w')
    if f then
      f:write(vim.json.encode(payload))
      f:write('\n')
      f:close()
    end
  end,
})
