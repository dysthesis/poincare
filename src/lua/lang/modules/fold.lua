local group = vim.api.nvim_create_augroup("lang_folds", {
  clear = true,
})

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

local function apply(bufnr)
  local enabled = vim.b[bufnr].lang_folds == true

  vim.wo.foldenable = enabled

  if enabled then
    vim.wo.foldmethod = "expr"
    vim.wo.foldexpr = vim.treesitter.foldexpr
  end
end

vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
  group = group,
  callback = function(event)
    apply(event.buf)
  end,
})

vim.api.nvim_create_autocmd("CursorMoved", {
  group = group,
  callback = function(event)
    if vim.b[event.buf].lang_folds == true and vim.fn.foldclosed(".") ~= -1 then
      vim.cmd("silent! normal! zv")
    end
  end,
})

return function(lang, enabled)
  assert(enabled == true, "fold must be true")

  for _, filetype in ipairs(lang.filetypes) do
    local ts_lang = vim.treesitter.language.get_lang(filetype) or filetype

    vim.treesitter.query.set(ts_lang, "folds", query_for(ts_lang))
  end

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = lang.filetypes,

    callback = function(event)
      vim.b[event.buf].lang_folds = true
      apply(event.buf)
      vim.wo.foldlevel = 0
    end,
  })
end
