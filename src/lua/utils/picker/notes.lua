local picker = require('utils.picker.core')

local producer = "zk list -P -q --format='{{title}}\t{{path}}'"
local preview = 'CLICOLOR_FORCE=1 COLORTERM=truecolor glow {2}'
local default_extra = "--delimiter='\t' --with-nth=1"
local parse = function(lines)
  return vim.tbl_map(vim.trim, lines)
end

local M = {}

M.run = function(sink, extra)
  picker.run {
    producer = producer,
    preview = preview,
    extra = default_extra .. ' ' .. extra,
    parse = parse,
    sink = sink,
  }
end

return M
