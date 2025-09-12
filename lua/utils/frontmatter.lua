local M = {}

M.DELIMITER_REGEX = '^%-%-%-%s*$'
M.ALTERNATIVE_END_FENCE = '^%.%.%.%s*$'

function M.get_frontmatter_text(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Check that frontmatter does exist
  if #lines == 0 or not lines[1]:match(M.DELIMITER_REGEX) then
    return nil
  end

  local body = {}

  -- Skip the delimiters, iterate over the body of the frontmatter
  for i = 2, #lines do
    local l = lines[i]
    if l:match(M.DELIMITER_REGEX) or l:match(M.ALTERNATIVE_END_FENCE) then
      return table.concat(body, '\n')
    end
    body[#body + 1] = l
  end
  return nil
end

function M.split_keypath(key)
  if type(key) == 'table' then
    return key
  end
  local t = {}
  for part in string.gmatch(key, '[^%.]+') do
    t[#t + 1] = part
  end
  return t
end

function M.get_in(tbl, path)
  local cur = tbl
  for _, k in ipairs(path) do
    if type(cur) ~= 'table' then
      return nil
    end
    cur = cur[k]
  end
  return cur
end

function M.get(key, opts)
  opts = opts or {}
  local text = M.get_frontmatter_text(opts.bufnr or 0)
  if not text then
    return nil, 'no front matter found'
  end
  local ok, yaml = pcall(require, 'lyaml')
  if not ok then
    return nil, 'lyaml not available (install with LuaRocks)'
  end
  local doc = yaml.load(text)
  return M.get_in(doc, M.split_keypath(key))
end

return M
