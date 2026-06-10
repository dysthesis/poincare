-- Probe (M4): LspAttach -> first DiagnosticChanged, ms, one sample per
-- process (a session attaches once). Needs lua-language-server on PATH
-- (devShell provides it); self-skips otherwise. The fixture project holds a
-- guaranteed unused-local diagnostic, so DiagnosticChanged must fire.
local function finish(payload)
  local out = vim.env.BENCH_OUT
  if out and out ~= '' then
    local f = assert(io.open(out, 'w'))
    payload.schema = 'poincare-lspprobe-v1'
    f:write(vim.json.encode(payload))
    f:write('\n')
    f:close()
  end
  vim.cmd('silent! qa!')
end

if vim.fn.executable('lua-language-server') ~= 1 then
  finish { skipped = 'lua-language-server not on PATH' }
  return
end

local files = vim.env.BENCH_FILES or 'bench/files'
local attached_at, elapsed_ms

vim.api.nvim_create_autocmd('LspAttach', {
  once = true,
  callback = function()
    attached_at = vim.uv.hrtime()
  end,
})
vim.api.nvim_create_autocmd('DiagnosticChanged', {
  callback = function()
    if attached_at and not elapsed_ms then
      elapsed_ms = (vim.uv.hrtime() - attached_at) / 1e6
    end
  end,
})

vim.cmd('silent! edit ' .. vim.fn.fnameescape(files .. '/lua-project/main.lua'))
vim.wait(30000, function()
  return elapsed_ms ~= nil
end, 50)

if elapsed_ms then
  finish { ms = elapsed_ms }
else
  finish { skipped = 'timeout waiting for LspAttach/DiagnosticChanged' }
end
