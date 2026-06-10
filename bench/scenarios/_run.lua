-- bench/scenarios/_run.lua — shared scenario runner (dofile'd by every
-- bench/scenarios/*.lua). Times the body end-to-end with vim.uv.hrtime,
-- records the result where bench/ledger.lua picks it up on VimLeavePre,
-- and always exits: qa! on success, cquit on failure so the driver sees a
-- non-zero exit code.
return function(name, body)
  local files = vim.env.BENCH_FILES or 'bench/files'
  -- +cmd args run before VimEnter and the scenario quits inside them, so
  -- the ledger's VimEnter hook never fires; post-boot RSS (M8) is sampled
  -- here instead — startup loads done, scenario work not yet started.
  -- _G is the channel to bench/ledger.lua: separate luafile chunks share
  -- no upvalues, so a named global is the mechanism, not an accident.
  -- selene: allow(global_usage)
  _G.BENCH_RSS_POST_BOOT = vim.uv.resident_set_memory()
  local started = vim.uv.hrtime()
  local ok, err = pcall(body, files)
  local ms = (vim.uv.hrtime() - started) / 1e6
  if ok then
    -- selene: allow(global_usage)
    _G.BENCH_SCENARIO = { name = name, ms = ms }
    vim.cmd('silent! qa!')
  else
    -- selene: allow(global_usage)
    _G.BENCH_SCENARIO = { name = name, error = tostring(err) }
    vim.api.nvim_echo({ { 'scenario ' .. name .. ' failed: ' .. tostring(err), 'ErrorMsg' } }, true, {})
    vim.cmd('cquit! 1')
  end
end
