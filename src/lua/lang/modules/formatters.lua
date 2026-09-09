local combinator = require("lib.combinator")

local formatters_by_ft = {}
local formatters = {}

local next_id = 0

local function leaf(spec)
  if type(spec) == "string" then
    return spec
  end

  assert(type(spec) == "table", "formatter must be a string or argv table")
  assert(type(spec[1]) == "string", "formatter argv must start with a name")

  local base = spec[1]

  if #spec == 1 then
    return base
  end

  local args = {}

  for i = 2, #spec do
    assert(
      type(spec[i]) == "string",
      "formatter argv must contain only strings"
    )

    args[#args + 1] = spec[i]
  end

  next_id = next_id + 1

  local name = ("lang_%s_%d"):format(base:gsub("[^%w_]", "_"), next_id)

  formatters[name] = {
    inherit = base,
    prepend_args = args,
  }

  return name
end

local function compile(spec)
  local kind, specs = combinator.unpack(spec)

  local result = {}

  for _, formatter in ipairs(specs) do
    result[#result + 1] = leaf(formatter)
  end

  if kind == "either" then
    result.stop_after_first = true
  end

  return result
end

require("lz.n").load({
  "conform.nvim",

  event = "BufWritePre",
  cmd = "ConformInfo",

  after = function()
    require("conform").setup({
      formatters_by_ft = formatters_by_ft,
      formatters = formatters,

      format_on_save = {
        timeout_ms = 1000,
        lsp_format = "never",
      },
    })
  end,
})

return function(lang, spec)
  local compiled = compile(spec)

  for _, filetype in ipairs(lang.filetypes) do
    formatters_by_ft[filetype] = compiled
  end
end
