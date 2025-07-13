local picker = require('utils.picker')

-- reuse your existing preview / parse / extra
local preview = 'CLICOLOR_FORCE=1 COLORTERM=truecolor glow {2}'
local default_extra = "--delimiter='\t' --with-nth=1"
local parse = function(lines)
  return vim.tbl_map(vim.trim, lines)
end

local M = {}

M.run = function(sink, extra)
  -- 1. grab the absolute path of the current note
  local current = vim.fn.expand('%:p')

  -- 2. shell-quote it so spaces/special chars are safe
  local quoted = vim.fn.shellescape(current)

  -- 3. build a 'backlinks' producer using --link-to
  local producer = string.format("zk list --link-to %s -P -q --format='{{title}}\t{{path}}'", quoted)

  -- 4. hand it off to your picker
  picker.run {
    producer = producer,
    preview = preview,
    extra = default_extra .. ' ' .. extra,
    parse = parse,
    sink = sink,
  }
end

return M
