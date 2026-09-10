---A complete formatter command. The first item is the executable name.
---`$FILENAME` is replaced just before execution. Formatter-specific stdin
---arguments are appended to a copied command after any custom arguments.
---@alias FormatterArgv string[]

---A formatter executable name, or a complete argv command.
---@alias FormatterCommand string|FormatterArgv

---One formatter executable name, or an ordered formatter pipeline.
---@alias FormatterSpec string|FormatterCommand[]

local FILENAME_PLACEHOLDER = "$FILENAME"

---@type table<string, FormatterArgv>
local STDIN_ARGS_BY_FORMATTER = {
  stylua = {
    "--search-parent-directories",
    "--respect-ignores",
    "--stdin-filepath",
    FILENAME_PLACEHOLDER,
    "-",
  },
}

local TIMEOUT_MS = 1000
local pipelines_by_ft = {}
local formatting = {}

local group = vim.api.nvim_create_augroup("lang_formatters", { clear = true })

local function fail(name, why)
  vim.notify(("formatter %q failed: %s"):format(name, why), vim.log.levels.WARN)
end

local function first_diagnostic(text)
  local line = text and text:match("%S[^\r\n]*")

  return line and line:sub(1, 160)
end

local function process_failure(reason, detail)
  local line = first_diagnostic(detail)

  return line and ("%s: %s"):format(reason, line) or reason
end

local function validate_output(text)
  if text:find("\0", 1, true) then
    return nil, "returned a NUL byte"
  end

  return text
end

local function run_formatter(argv, text, filename, cwd, deadline)
  local cmd = {}

  for i, arg in ipairs(argv) do
    cmd[i] = arg == FILENAME_PLACEHOLDER and filename or arg
  end

  local remaining = math.ceil((deadline - vim.uv.hrtime()) / 1e6)

  if remaining <= 0 then
    return nil, "timed out"
  end

  local ok, process = pcall(vim.system, cmd, {
    cwd = cwd,
    stdin = text,
  })

  if not ok then
    return nil, process_failure("could not start", process)
  end

  remaining = math.ceil((deadline - vim.uv.hrtime()) / 1e6)
  local expired = remaining <= 0
  local result = process:wait(math.max(remaining, 1))

  if expired or (result.code == 124 and result.signal == 9) then
    return nil, process_failure("timed out", result.stderr)
  end

  if result.signal ~= 0 then
    return nil,
      process_failure(
        ("terminated by signal %d"):format(result.signal),
        result.stderr
      )
  end

  if result.code ~= 0 then
    return nil,
      process_failure(("exit %d"):format(result.code), result.stderr)
  end

  return validate_output(result.stdout or "")
end

local function unchanged(bufnr, state)
  if
    not vim.api.nvim_buf_is_valid(bufnr)
    or not vim.api.nvim_buf_is_loaded(bufnr)
  then
    return false
  end

  local bo = vim.bo[bufnr]

  return vim.api.nvim_buf_get_changedtick(bufnr) == state.tick
    and vim.api.nvim_buf_get_name(bufnr) == state.name
    and bo.filetype == state.filetype
    and bo.buftype == ""
    and bo.modifiable
    and not bo.binary
end

local function apply_formatted_lines(bufnr, old_lines, new_lines)
  if vim.deep_equal(old_lines, new_lines) then
    return
  end

  -- A buffer line array includes its final line, so terminate both diff inputs.
  local hunks = vim.text.diff(
    table.concat(old_lines, "\n") .. "\n",
    table.concat(new_lines, "\n") .. "\n",
    {
      result_type = "indices",
      algorithm = "histogram",
    }
  )

  if hunks == nil then
    return
  end

  -- Work bottom-up so mutations do not shift the coordinates of earlier hunks.
  -- Run :undojoin in the target buffer's undo context, even when it is not
  -- current.
  vim.api.nvim_buf_call(bufnr, function()
    for i = #hunks, 1, -1 do
      local old_line, old_count, new_line, new_count = unpack(hunks[i])

      -- Diff lines are one-based. For an insertion, old_line names the
      -- preceding line, which is already the zero-based insertion row.
      local start_row = old_line - (old_count > 0 and 1 or 0)
      local end_row = start_row + old_count
      local replacement = new_count == 0 and {}
        or vim.list_slice(new_lines, new_line, new_line + new_count - 1)

      if i < #hunks then
        -- The first mutation starts an undo entry; subsequent hunks join it.
        vim.cmd.undojoin()
      end

      vim.api.nvim_buf_set_lines(bufnr, start_row, end_row, false, replacement)
    end
  end)
end

local function format(bufnr)
  local bo = vim.bo[bufnr]
  local pipeline = pipelines_by_ft[bo.filetype]

  if not pipeline or bo.buftype ~= "" or not bo.modifiable or bo.binary then
    return
  end

  local state = {
    tick = vim.api.nvim_buf_get_changedtick(bufnr),
    name = vim.api.nvim_buf_get_name(bufnr),
    filetype = bo.filetype,
  }
  local cwd = state.name == "" and vim.fn.getcwd() or vim.fs.dirname(state.name)
  local filename = state.name ~= "" and state.name
    or ("%s/unnamed.%s"):format(cwd, state.filetype)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, "\n") .. "\n"
  local deadline = vim.uv.hrtime() + TIMEOUT_MS * 1e6

  for _, argv in ipairs(pipeline) do
    local output, reason =
      run_formatter(argv, text, filename, cwd, deadline)

    if not output then
      fail(argv[1], reason)
      return
    end

    if output:match("^%s*$") and not text:match("^%s*$") then
      fail(argv[1], "returned no output")
      return
    end

    text = output
  end

  if not unchanged(bufnr, state) then
    fail(pipeline[1][1], "buffer changed while formatting; discarded output")
    return
  end

  local new_lines = vim.split(text, "\r?\n")

  if #new_lines > 1 and new_lines[#new_lines] == "" then
    new_lines[#new_lines] = nil
  end

  apply_formatted_lines(bufnr, lines, new_lines)
end

vim.api.nvim_create_autocmd("BufWritePre", {
  group = group,
  callback = function(event)
    if formatting[event.buf] then
      return
    end

    formatting[event.buf] = true
    local ok, err = xpcall(format, debug.traceback, event.buf)
    formatting[event.buf] = nil

    if not ok then
      vim.notify("formatter failed unexpectedly: " .. err, vim.log.levels.WARN)
    end
  end,
})

---@param entry FormatterCommand
---@return FormatterArgv
local function compile_entry(entry)
  local argv = {}

  if type(entry) == "string" then
    argv[1] = entry
  else
    assert(
      type(entry) == "table" and vim.islist(entry),
      "formatter must be a string or argv list"
    )
    assert(
      type(entry[1]) == "string",
      "formatter argv must start with a name"
    )

    for _, arg in ipairs(entry) do
      assert(
        type(arg) == "string",
        "formatter argv must contain only strings"
      )
      argv[#argv + 1] = arg
    end
  end

  vim.list_extend(argv, STDIN_ARGS_BY_FORMATTER[argv[1]] or {})
  return argv
end

---@param spec FormatterSpec
---@return FormatterArgv[]
local function compile(spec)
  if type(spec) == "string" then
    spec = { spec }
  else
    assert(
      type(spec) == "table" and vim.islist(spec),
      "formatters must be a string or list"
    )
  end

  local pipeline = {}

  for _, entry in ipairs(spec) do
    local argv = compile_entry(entry)

    if vim.fn.executable(argv[1]) == 1 then
      pipeline[#pipeline + 1] = argv
    else
      vim.notify(
        ("formatter %q is not installed; skipping"):format(argv[1]),
        vim.log.levels.WARN
      )
    end
  end

  return pipeline
end

---Register an ordered formatter pipeline for a language. Nested argv commands
---put custom arguments before any formatter-specific stdin arguments.
---@param lang { filetypes: string[] }
---@param spec FormatterSpec
return function(lang, spec)
  assert(
    type(lang) == "table"
      and type(lang.filetypes) == "table"
      and vim.islist(lang.filetypes),
    "lang.filetypes must be a list"
  )
  local pipeline = compile(spec)

  for _, filetype in ipairs(lang.filetypes) do
    assert(type(filetype) == "string", "filetype must be a string")
    pipelines_by_ft[filetype] = #pipeline > 0 and pipeline or nil
  end
end
