-- Probe (M5): treesitter full-reparse cost, ns/parse, per shipped grammar.
-- Standalone (no ledger needed): writes raw samples to $BENCH_OUT;
-- bench/stats.lua tsparse aggregates. BENCH_TS_RUNS parses per grammar
-- (default 100), each forced by invalidate(true).
local langs = {
  c = 'small.c',
  go = 'small.go',
  just = 'justfile',
  lean = 'small.lean',
  lua = 'small.lua',
  markdown = 'small.md',
  nix = 'small.nix',
  python = 'small.py',
  rust = 'small.rs',
  zig = 'small.zig',
}

local files = vim.env.BENCH_FILES or 'bench/files'
local runs = tonumber(vim.env.BENCH_TS_RUNS) or 100
local per_lang, skipped = {}, {}

for lang, fname in pairs(langs) do
  vim.cmd('silent! edit ' .. vim.fn.fnameescape(files .. '/' .. fname))
  local buf = vim.api.nvim_get_current_buf()
  local ok, parser = pcall(vim.treesitter.get_parser, buf, lang)
  if ok and parser then
    parser:parse(true) -- warm: first parse pays query/lib load
    local samples = {}
    for i = 1, runs do
      parser:invalidate(true)
      local started = vim.uv.hrtime()
      parser:parse(true)
      samples[i] = vim.uv.hrtime() - started
    end
    per_lang[lang] = samples
  else
    skipped[#skipped + 1] = lang
  end
  vim.cmd('silent! bwipeout!')
end

local out = vim.env.BENCH_OUT
if out and out ~= '' then
  local f = assert(io.open(out, 'w'))
  f:write(vim.json.encode { schema = 'poincare-tsprobe-v1', runs = runs, per_lang = per_lang, skipped = skipped })
  f:write('\n')
  f:close()
end
vim.cmd('silent! qa!')
