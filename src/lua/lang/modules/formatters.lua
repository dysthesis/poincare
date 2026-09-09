local formatters_by_ft = {}
local formatters = {}

local next_id = 0

-- Returns the conform formatter name and the binary it needs.
local function leaf(spec)
  if type(spec) == "string" then
    return spec, spec
  end

  assert(type(spec) == "table", "formatter must be a string or argv table")
  assert(type(spec[1]) == "string", "formatter argv must start with a name")

  local base = spec[1]

  if #spec == 1 then
    return base, base
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

  return name, base
end

-- A spec is one formatter or a list of them; an argv leaf nests one level
-- (`{ { "shfmt", "-i", "2" } }`). Every available formatter runs, in order.
local function compile(spec)
  if type(spec) == "string" then
    spec = { spec }
  end

  local result = {}

  for _, entry in ipairs(spec) do
    local name, bin = leaf(entry)

    -- simplification: a formatter's name is assumed to be its executable;
    -- a conform formatter whose `command` differs is wrongly skipped.
    -- Upgrade path: resolve through conform's registry after plugin load.
    if vim.fn.executable(bin) == 1 then
      result[#result + 1] = name
    else
      vim.notify(
        ("formatter %q is not installed; skipping"):format(bin),
        vim.log.levels.WARN
      )
    end
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
