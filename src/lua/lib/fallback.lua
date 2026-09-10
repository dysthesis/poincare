local M = {}

function M.first(spec, available)
  if type(spec) == "string" then
    spec = { spec }
  end

  for _, candidate in ipairs(spec) do
    if available(candidate) then
      return candidate
    end
  end
end

function M.warn(kind, lang, spec)
  vim.notify(
    ("no %s available for %s (tried: %s)"):format(
      kind,
      table.concat(lang.filetypes, ", "),
      table.concat(spec, ", ")
    ),
    vim.log.levels.WARN
  )
end

return M
