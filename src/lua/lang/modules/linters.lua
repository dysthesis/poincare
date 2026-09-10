local M = {}

local linters_by_ft = {}

local function run(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.api.nvim_buf_call(bufnr, function()
    require("lint").try_lint()
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
  }, {
    group = group,

    callback = function(event)
      run(event.buf)
    end,
  })

  -- The event which caused lz.n to load nvim-lint may already
  -- be in progress, so lint the current buffer once explicitly.
  run(vim.api.nvim_get_current_buf())
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
