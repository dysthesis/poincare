local M = {}

local linters_by_ft = {}

local function available(linter)
  local cmd = linter.cmd

  if type(cmd) == "function" then
    cmd = cmd()
  end

  return type(cmd) == "string" and vim.fn.executable(cmd) == 1
end

local function run(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.api.nvim_buf_call(bufnr, function()
    require("lint").try_lint(nil, {
      filter = available,
    })
  end)
end

require("lz.n").load({
  "nvim-lint",

  event = {
    "BufReadPost",
    "BufWritePost",
  },
  after = function()
    require("lang.modules.linters").setup()
  end,
})

function M.setup()
  local lint = require("lint")

  for ft, linters in pairs(linters_by_ft) do
    lint.linters_by_ft[ft] = linters
  end

  local group = vim.api.nvim_create_augroup("lang_linters", {
    clear = true,
  })

  vim.api.nvim_create_autocmd({
    "BufReadPost",
    "BufWritePost",
    "FileType",
  }, {
    group = group,

    callback = function(event)
      if vim.bo[event.buf].filetype ~= "" then
        run(event.buf)
      end
    end,
  })

  -- The lazy-load event may already be in progress. If filetype detection
  -- has not run yet, the FileType autocmd above handles this first buffer.
  local current = vim.api.nvim_get_current_buf()
  if vim.bo[current].filetype ~= "" then
    run(current)
  end

end

function M.register(lang, spec)
  if type(spec) == "string" then
    spec = { spec }
  end

  for _, name in ipairs(spec) do
    assert(type(name) == "string", "linter must be a name")
  end

  for _, ft in ipairs(lang.filetypes) do
    linters_by_ft[ft] = spec
  end
end

return setmetatable(M, {
  __call = function(_, ...)
    return M.register(...)
  end,
})
