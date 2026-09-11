local group = vim.api.nvim_create_augroup("lang_folds", {
  clear = true,
})

local function capture_at(bufnr, row, col)
  local best
  local priority = -1

  for _, capture in ipairs(vim.treesitter.get_captures_at_pos(bufnr, row, col)) do
    local p = capture.metadata.priority

    if type(p) ~= "number" then
      p = 100
    end

    if p >= priority then
      best = "@" .. capture.capture
      priority = p
    end
  end

  return best
end

local function highlighted_line(bufnr, row, text)
  if text == "" then
    return {}
  end

  local chunks = {}
  local start = 0
  local hl = capture_at(bufnr, row, 0)

  for col = 1, #text do
    local next_hl = col < #text and capture_at(bufnr, row, col) or nil

    if next_hl ~= hl then
      chunks[#chunks + 1] = {
        text:sub(start + 1, col),
        hl,
      }

      start = col
      hl = next_hl
    end
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
