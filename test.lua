local tachyon = require('tachyon')

local function CUSTOM_MATCH(stritems, inds, query_tbl, opts)
  local engine = tachyon.new(stritems, { match_paths = true, literal = false })
  local q = table.concat(query_tbl, '')
  local limit = opts and opts.limit or nil
  print('In tachyon!')
  return engine:match(inds, q, limit)
end

local MiniPick = require('mini.pick')
MiniPick.start { source = { items = vim.fn.readdir('.'), match = CUSTOM_MATCH } }
