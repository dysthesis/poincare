local combinator = require("lib.combinator")

local function executable(name)
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

local function enable(name)
  assert(
    type(name) == "string",
    "LSP specification must be a configuration name"
  )

  assert(
    executable(name),
    ("LSP %q is configured but its executable is unavailable"):format(name)
  )

  vim.lsp.enable(name)
end

return function(_, spec)
  local kind, servers = combinator.unpack(spec)

  if kind == "either" then
    for _, server in ipairs(servers) do
      assert(type(server) == "string")

      if executable(server) then
        vim.lsp.enable(server)
        return
      end
    end

    error("None of the fallback LSPs are available.")
  end

  for _, server in ipairs(servers) do
    enable(server)
  end
end
