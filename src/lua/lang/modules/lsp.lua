local function available(name)
  local config = vim.lsp.config[name]

  assert(config, ("no LSP configuration named %q"):format(name))

  local cmd = config.cmd

  -- Function-valued commands cannot be inspected statically.
  if type(cmd) == "function" then
    return true
  end

  assert(
    type(cmd) == "table" and type(cmd[1]) == "string",
    ("LSP %q has no inspectable command"):format(name)
  )

  return vim.fn.executable(cmd[1]) == 1
end

-- A spec is one server or a list of fallbacks; the first available wins.
return function(lang, spec)
  if type(spec) == "string" then
    spec = { spec }
  end

  for _, name in ipairs(spec) do
    assert(
      type(name) == "string",
      "LSP specification must be a configuration name"
    )

    if available(name) then
      vim.lsp.enable(name)
      return
    end
  end

  vim.notify(
    ("no LSP available for %s (tried: %s)"):format(
      table.concat(lang.filetypes, ", "),
      table.concat(spec, ", ")
    ),
    vim.log.levels.WARN
  )
end
