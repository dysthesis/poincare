local function available(name)
  local config = vim.lsp.config[name]

  if not config then
    return false
  end

  local cmd = config.cmd

  if type(cmd) == "function" then
    return true
  end

  if type(cmd) ~= "table" or type(cmd[1]) ~= "string" then
    return false
  end

  return vim.fn.executable(cmd[1]) == 1
end

local fallback = require("lib.fallback")

-- A spec is one server or a list of fallbacks; the first available wins.
return function(lang, spec)
  if type(spec) == "string" then
    spec = { spec }
  end

  for _, name in ipairs(spec) do
    assert(type(name) == "string", "LSP must be a configuration name")
  end

  local name = fallback.first(spec, available)

  if name then
    vim.lsp.enable(name)
    return
  end

  fallback.warn("LSP", lang, spec)
end
