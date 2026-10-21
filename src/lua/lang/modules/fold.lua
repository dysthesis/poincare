local group = vim.api.nvim_create_augroup("lang_folds", {
  clear = true,
})

local function highlighted_line(bufnr, row, text)
  if text == "" then
    return {}
  end

  local highlighter = vim.treesitter.highlighter.active[bufnr]

  if not highlighter then
    return { { text } }
  end

  local events = {}
  local order = 0

  highlighter.tree:for_each_tree(function(tstree, tree)
    if not tstree then
      return
    end

    local root = tstree:root()
    local root_start, _, root_end = root:range()

    if root_start > row or root_end < row then
      return
    end

    local query = highlighter:get_query(tree:lang()):query()

    if not query then
      return
    end

    for id, node, metadata in
      query:iter_captures(root, highlighter.bufnr, row, row + 1)
    do
      local name = query.captures[id]
      local start_row, start_col, end_row, end_col = node:range()

      if name and start_row <= row and end_row >= row then
        -- Match get_captures_at_pos: raw node ranges, in byte coordinates.
        local first = start_row == row and math.min(start_col, #text) or 0
        local last = end_row == row and math.min(end_col, #text) or #text

        if first < last then
          local priority = metadata.priority

          if type(priority) ~= "number" then
            priority = 100
          end

          order = order + 1
          local capture = { priority = priority, hl = "@" .. name }

          -- Ending events remove the capture before the next interval.
          events[#events + 1] = { first, order, capture }
          events[#events + 1] = { last, order }
        end
      end
    end
  end)

  table.sort(events, function(a, b)
    return a[1] < b[1]
  end)

  local chunks = {}
  local active = {}
  local start = 0
  local hl
  local index = 1

  while index <= #events do
    local col = events[index][1]

    repeat
      local event = events[index]
      active[event[2]] = event[3]
      index = index + 1
    until index > #events or events[index][1] ~= col

    local next_hl
    local priority = -1
    local latest = 0

    for capture_order, capture in pairs(active) do
      local p = capture.priority

      if p > priority or (p == priority and capture_order > latest) then
        next_hl = capture.hl
        priority = p
        latest = capture_order
      end
    end

    if next_hl ~= hl then
      if start < col then
        chunks[#chunks + 1] = { text:sub(start + 1, col), hl }
      end

      start = col
      hl = next_hl
    end
  end

  -- Flush plain text too: nil is a highlight, not an end-of-line sentinel.
  if start < #text then
    chunks[#chunks + 1] = { text:sub(start + 1), hl }
  end

  return chunks
end

local function foldtext()
  local bufnr = vim.api.nvim_get_current_buf()
  local row = vim.v.foldstart - 1

  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""

  line = line:gsub("%s+$", "")

  local chunks = highlighted_line(bufnr, row, line)
  local lines = vim.v.foldend - vim.v.foldstart + 1

  chunks[#chunks + 1] = {
    ("  … %d lines …"):format(lines),
    "Comment",
  }

  -- C/Rust/Go/etc.: visually close the opening `{`.
  if line:match("{%s*$") then
    chunks[#chunks + 1] = { " }", "@punctuation.bracket" }
  end

  return chunks
end

local function query_for(lang)
  local path = vim.api.nvim_get_runtime_file(
    ("queries/%s/fold.scm"):format(lang),
    false
  )[1]

  assert(path, ("no method-folds query for %s"):format(lang))

  local file = assert(io.open(path, "r"))
  local query = file:read("*a")
  file:close()

  return query
end

local enabled_filetypes = {}

local function apply()
  local enabled = enabled_filetypes[vim.bo.filetype] == true

  vim.wo.foldenable = enabled

  if not enabled then
    return
  end

  vim.wo.foldmethod = "expr"
  vim.wo.foldexpr = vim.treesitter.foldexpr
  vim.wo.foldtext = foldtext

  -- Keep your fold arrows.
  vim.wo.foldcolumn = "1"

  vim.opt_local.fillchars:append({
    fold = " ",
    foldopen = "",
    foldclose = "",
    foldsep = " ",
  })
end

vim.api.nvim_create_autocmd({ "FileType", "BufEnter", "WinEnter" }, {
  group = group,
  callback = apply,
})

return function(lang, enabled)
  assert(enabled == true, "fold must be true")

  for _, filetype in ipairs(lang.filetypes) do
    enabled_filetypes[filetype] = true

    local ts_lang = vim.treesitter.language.get_lang(filetype) or filetype

    vim.treesitter.query.set(ts_lang, "folds", query_for(ts_lang))
  end

  -- `FileType` may already have fired for the current buffer.
  apply()
  vim.wo.foldlevel = 0
end
