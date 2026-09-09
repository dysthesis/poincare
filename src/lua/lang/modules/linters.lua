local combinator = require("lib.combinator")

local linters_by_ft = {}
local namespaces = {}
local processes = {}
local generations = {}

local group = vim.api.nvim_create_augroup("lang_linters", {
  clear = true,
})

local function executable(name)
  return vim.fn.executable(name) == 1
end

local function load(name)
  local linter = require("lang.linters." .. name)

  assert(
    type(linter.cmd) == "function",
    ("linter %q must define cmd(ctx)"):format(name)
  )

  assert(
    type(linter.parse) == "function",
    ("linter %q must define parse(result, ctx)"):format(name)
  )

  return linter
end

local function namespace(name)
  local ns = namespaces[name]

  if ns == nil then
    ns = vim.api.nvim_create_namespace("lang/linter/" .. name)
    namespaces[name] = ns
  end

  return ns
end

local function key(bufnr, name)
  return ("%d:%s"):format(bufnr, name)
end

local function context(bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)

  if filename == "" then
    return nil
  end

  return {
    bufnr = bufnr,
    filename = filename,
    cwd = vim.fs.dirname(filename),
  }
end

local function lint(name, bufnr)
  local ctx = context(bufnr)

  if not ctx then
    return
  end

  local linter = load(name)
  local cmd = linter.cmd(ctx)

  assert(
    type(cmd) == "table" and type(cmd[1]) == "string",
    ("linter %q returned an invalid command"):format(name)
  )

  local process_key = key(bufnr, name)

  -- Kill an older invocation. Its output is already obsolete.
  local previous = processes[process_key]

  if previous then
    previous:kill(15)
  end

  generations[process_key] = (generations[process_key] or 0) + 1

  local generation = generations[process_key]

  local opts = {
    cwd = ctx.cwd,
    text = true,
  }

  if linter.stdin then
    opts.stdin =
      table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  end

  processes[process_key] = vim.system(cmd, opts, function(result)
    vim.schedule(function()
      -- A newer lint invocation superseded this one.
      if generations[process_key] ~= generation then
        return
      end

      processes[process_key] = nil

      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      local diagnostics = linter.parse(result, ctx)

      vim.diagnostic.set(namespace(name), bufnr, diagnostics)
    end)
  end)
end

local function run(bufnr)
  local ft = vim.bo[bufnr].filetype
  local linters = linters_by_ft[ft]

  if not linters then
    return
  end

  for _, name in ipairs(linters) do
    lint(name, bufnr)
  end
end

vim.api.nvim_create_autocmd({
  "BufReadPost",
  "BufWritePost",
}, {
  group = group,

  callback = function(event)
    run(event.buf)
  end,
})

return function(lang, spec)
  local kind, names = combinator.unpack(spec)
  local selected = {}

  if kind == "either" then
    for _, name in ipairs(names) do
      assert(type(name) == "string")

      if executable(name) then
        selected[1] = name
        break
      end
    end

    assert(#selected > 0, "none of the fallback linters are available")
  else
    for _, name in ipairs(names) do
      assert(type(name) == "string")

      assert(executable(name), ("linter %q is unavailable"):format(name))

      selected[#selected + 1] = name
    end
  end

  for _, ft in ipairs(lang.filetypes) do
    linters_by_ft[ft] = selected
  end
end
