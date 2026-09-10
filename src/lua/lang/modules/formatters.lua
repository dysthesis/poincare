---A complete formatter command. The first item is the executable name.
---`$FILENAME` is replaced just before execution.
---@alias FormatterArgv string[]

---A formatter executable name, or a complete argv command.
---@alias FormatterCommand string|FormatterArgv

---One formatter executable name, or an ordered formatter pipeline.
---@alias FormatterSpec string|FormatterCommand[]

local FILENAME_PLACEHOLDER = "$FILENAME"
local DIAGNOSTIC_MAX_LENGTH = 160

local TIMEOUT_MS = 1000
local pipelines_by_ft = {}
local formats_in_progress = {}

local group = vim.api.nvim_create_augroup("lang_formatters", { clear = true })

local function notify_formatter_failure(command, reason)
  vim.notify(
    ("formatter %q failed: %s"):format(command, reason),
    vim.log.levels.WARN
  )
end

local function notify_orchestration_warning(reason)
  vim.notify("formatter orchestration: " .. reason, vim.log.levels.WARN)
end

local function first_diagnostic(text)
  local line = text and text:match("%S[^\r\n]*")

  return line and line:sub(1, DIAGNOSTIC_MAX_LENGTH)
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

local function expand_formatter_command(argv, filename)
  local cmd = {}

  for i, arg in ipairs(argv) do
    cmd[i] = arg == FILENAME_PLACEHOLDER and filename or arg
  end

  return cmd
end

local function wait_for_process(process, deadline)
  local remaining = math.ceil((deadline - vim.uv.hrtime()) / 1e6)
  local deadline_expired = remaining <= 0
  local result = process:wait(math.max(remaining, 1))
  local timed_out = deadline_expired
    or (result.code == 124 and result.signal == 9)

  return result, timed_out
end

local function interpret_process_result(result, timed_out)
  if timed_out then
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
    return nil, process_failure(("exit %d"):format(result.code), result.stderr)
  end

  return validate_output(result.stdout or "")
end

local function run_formatter(snapshot, argv, text, deadline)
  local remaining = math.ceil((deadline - vim.uv.hrtime()) / 1e6)

  if remaining <= 0 then
    return nil, "timed out"
  end

  local cmd = expand_formatter_command(argv, snapshot.filename)
  local ok, process = pcall(vim.system, cmd, {
    cwd = snapshot.cwd,
    stdin = text,
  })

  if not ok then
    return nil, process_failure("could not start", process)
  end

  return interpret_process_result(wait_for_process(process, deadline))
end

local function buffer_is_eligible(bufnr)
  if
    not vim.api.nvim_buf_is_valid(bufnr)
    or not vim.api.nvim_buf_is_loaded(bufnr)
  then
    return false
  end

  local bo = vim.bo[bufnr]

  return bo.buftype == "" and bo.modifiable and not bo.binary
end

local function buffer_lines_to_formatter_input(lines)
  -- Buffer lines do not encode a terminal newline. Give formatters exactly one;
  -- 'endofline' remains buffer metadata and is therefore left unchanged.
  return table.concat(lines, "\n") .. "\n"
end

local function formatter_output_to_buffer_lines(text)
  local lines = vim.split(text, "\r?\n")

  -- A terminal newline produces one sentinel empty item. Remove exactly that
  -- item; preceding empty items represent real trailing buffer lines.
  if #lines > 1 and lines[#lines] == "" then
    lines[#lines] = nil
  end

  return lines
end

local function capture_buffer_snapshot(bufnr)
  if not buffer_is_eligible(bufnr) then
    return
  end

  local bo = vim.bo[bufnr]
  local pipeline = pipelines_by_ft[bo.filetype]

  if not pipeline then
    return
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  local cwd = name == "" and vim.fn.getcwd() or vim.fs.dirname(name)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  return {
    bufnr = bufnr,
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    name = name,
    filetype = bo.filetype,
    pipeline = pipeline,
    cwd = cwd,
    filename = name ~= "" and name
      or ("%s/unnamed.%s"):format(cwd, bo.filetype),
    lines = lines,
    formatter_input = buffer_lines_to_formatter_input(lines),
  }
end

local function buffer_matches_snapshot(snapshot)
  if not buffer_is_eligible(snapshot.bufnr) then
    return false
  end

  local bo = vim.bo[snapshot.bufnr]

  return vim.api.nvim_buf_get_changedtick(snapshot.bufnr)
      == snapshot.changedtick
    and vim.api.nvim_buf_get_name(snapshot.bufnr) == snapshot.name
    and bo.filetype == snapshot.filetype
end

local function would_erase_non_whitespace(input, output)
  return output:match("^%s*$") ~= nil and input:match("^%s*$") == nil
end

local function run_pipeline(snapshot)
  local text = snapshot.formatter_input
  local deadline = vim.uv.hrtime() + TIMEOUT_MS * 1e6

  for _, argv in ipairs(snapshot.pipeline) do
    local output, reason = run_formatter(snapshot, argv, text, deadline)

    if not output then
      return nil, argv[1], reason
    end

    if would_erase_non_whitespace(text, output) then
      return nil, argv[1], "returned only whitespace for non-whitespace input"
    end

    text = output
  end

  return text
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

local function format_buffer(bufnr)
  local snapshot = capture_buffer_snapshot(bufnr)

  if not snapshot then
    return
  end

  local formatted_text, failed_command, failure_reason = run_pipeline(snapshot)

  if not formatted_text then
    notify_formatter_failure(failed_command, failure_reason)
    return
  end

  if not buffer_matches_snapshot(snapshot) then
    notify_orchestration_warning(
      "buffer changed while formatting; discarded output"
    )
    return
  end

  local formatted_lines = formatter_output_to_buffer_lines(formatted_text)
  apply_formatted_lines(snapshot.bufnr, snapshot.lines, formatted_lines)
end

vim.api.nvim_create_autocmd("BufWritePre", {
  group = group,
  callback = function(event)
    if formats_in_progress[event.buf] then
      return
    end

    formats_in_progress[event.buf] = true
    local ok, err = xpcall(format_buffer, debug.traceback, event.buf)
    formats_in_progress[event.buf] = nil

    if not ok then
      notify_orchestration_warning("unexpected error: " .. err)
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
    assert(type(entry[1]) == "string", "formatter argv must start with a name")

    for _, arg in ipairs(entry) do
      assert(type(arg) == "string", "formatter argv must contain only strings")
      argv[#argv + 1] = arg
    end
  end

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

---Register an ordered formatter pipeline for a language.
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
