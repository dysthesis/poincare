local M = {}

function M.unpack(spec)
  if type(spec) ~= "table" then
    return "one", { spec }
  end

  local all = spec.all
  local either = spec.either

  -- A table without either combinator is one leaf.
  if all == nil and either == nil then
    return "one", { spec }
  end

  assert(
    not (all ~= nil and either ~= nil),
    "cannot combine `all` and `either`"
  )

  local values = all or either

  assert(type(values) == "table", "`all`/`either` must contain a table")
  assert(#values > 0, "`all`/`either` cannot be empty")

  return all ~= nil and "all" or "either", values
end

return M
