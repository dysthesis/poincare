---A complete formatter command. The first item is the executable name.
---`$FILENAME` is replaced just before execution.
---@alias FormatterArgv string[]

---A formatter executable name, or a complete argv command.
---@alias FormatterCommand string|FormatterArgv

---One formatter executable name, or an ordered list of fallbacks.
---@alias FormatterSpec string|FormatterCommand[]

local FILENAME_PLACEHOLDER = "$FILENAME"
local DIAGNOSTIC_MAX_LENGTH = 160

local TIMEOUT_MS = 1000
local formatters_by_ft = {}
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

local function await_process(cmd, opts)
  return vim.async.pawait(function(done)
    local callback_received = false
    local close_callbacks = {}
    local closing = false
    local settled = false
    local process
    local handle = {}

    local function finish_close()
      if not settled then
        return
      end

      local callbacks = close_callbacks
      close_callbacks = {}

      for _, callback in ipairs(callbacks) do
        callback()
      end
    end

    process = vim.system(cmd, opts, function(result)
      callback_received = true
      vim.schedule(function()
        settled = true
        done(result)
        finish_close()
      end)
    end)

    function handle:is_closing()
      return closing
    end

    function handle:close(callback)
      if callback then
        close_callbacks[#close_callbacks + 1] = callback
      end

      if not closing then
        closing = true

        if not callback_received then
          pcall(process.kill, process, 9)
        end
      end

      finish_close()
    end

    return handle
  end)
end

local function is_timeout_error(err)
  return err == "timeout"
    or (type(err) == "string" and err:match("^timeout\nstack traceback:"))
      ~= nil
end

local function interpret_process_result(result)
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

local function run_formatter(snapshot, argv, text)
  local cmd = expand_formatter_command(argv, snapshot.filename)
  local started, result = await_process(cmd, {
    cwd = snapshot.cwd,
    stdin = text,
  })

  if not started then
    return nil, process_failure("could not start", result)
  end

  return interpret_process_result(result)
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
  local formatter = formatters_by_ft[bo.filetype]

  if not formatter then
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
    formatter = formatter,
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

local function format_snapshot(snapshot, state)
  state.active_formatter = snapshot.formatter[1]
  local output, reason =
    run_formatter(snapshot, snapshot.formatter, snapshot.formatter_input)

  if not output then
    return nil, reason
  end

  if would_erase_non_whitespace(snapshot.formatter_input, output) then
    return nil, "returned only whitespace for non-whitespace input"
  end

  return output
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

local function format_buffer(bufnr, state)
  local snapshot = capture_buffer_snapshot(bufnr)

  if not snapshot then
    return
  end

  local formatter = vim.async.run(format_snapshot, snapshot, state)
  local formatted_text, failure_reason =
    vim.async.timeout(TIMEOUT_MS, formatter)
  vim.async.await(vim.schedule)

  if not formatted_text then
    notify_formatter_failure(snapshot.formatter[1], failure_reason)
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
    local state = {}
    local started, task = pcall(vim.async.run, format_buffer, event.buf, state)
    local ok, err

    if started then
      ok, err = task:pwait()

      if not task:completed() then
        task:close()
        task:pwait()
      end
    else
      ok, err = false, task
    end
    formats_in_progress[event.buf] = nil

    if not ok then
      if is_timeout_error(err) then
        notify_formatter_failure(state.active_formatter, "timed out")
      else
        notify_orchestration_warning("unexpected error: " .. tostring(err))
      end
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
---@return FormatterArgv? selected
---@return string[] tried
local function compile(spec)
  if type(spec) == "string" then
    spec = { spec }
  else
    assert(
      type(spec) == "table" and vim.islist(spec),
      "formatters must be a string or list"
    )
  end

  local selected
  local tried = {}

  for _, entry in ipairs(spec) do
    local argv = compile_entry(entry)
    tried[#tried + 1] = argv[1]

    if not selected and vim.fn.executable(argv[1]) == 1 then
      selected = argv
    end
  end

  return selected, tried
end

local fallback = require("lib.fallback")

---Register ordered formatter fallbacks for a language.
---@param lang { filetypes: string[] }
---@param spec FormatterSpec
return function(lang, spec)
  assert(
    type(lang) == "table"
      and type(lang.filetypes) == "table"
      and vim.islist(lang.filetypes),
    "lang.filetypes must be a list"
  )

  for _, filetype in ipairs(lang.filetypes) do
    assert(type(filetype) == "string", "filetype must be a string")
  end

  local formatter, tried = compile(spec)

  if not formatter and #tried > 0 then
    fallback.warn("formatter", lang, tried)
  end

  for _, filetype in ipairs(lang.filetypes) do
    formatters_by_ft[filetype] = formatter
  end
end
