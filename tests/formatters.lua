local MiniTest = require("mini.test")

local test_file = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local root = vim.fs.dirname(vim.fs.dirname(test_file))

local register = dofile(root .. "/src/lua/lang/modules/formatters.lua")
local lua_spec = dofile(root .. "/src/lua/lang/specs/lua.lua")
local original_notify = vim.notify
vim.notify = function() end

local dir = assert(vim.uv.fs_mkdtemp("/tmp/poincare-formatters-XXXXXX"))
local T = MiniTest.new_set({
  hooks = {
    post_once = function()
      vim.notify = original_notify
      vim.fn.delete(dir, "rf")
    end,
  },
})

local function case(filetype, lines, spec)
  local bufnr = vim.api.nvim_create_buf(true, false)

  vim.bo[bufnr].filetype = filetype

  if lines then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end

  register({ filetypes = { filetype } }, spec)

  return bufnr
end

local function write(bufnr, name)
  vim.v.errmsg = ""
  vim.api.nvim_buf_set_name(bufnr, name)
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("silent write!")
  end)
  assert(vim.v.errmsg == "", "write raised a callback error: " .. vim.v.errmsg)
end

local function assert_lines(bufnr, lines, what)
  local got = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  assert(
    vim.deep_equal(got, lines),
    ("%s: got %s"):format(what, vim.inspect(got))
  )
end

local function assert_file(path, content, what)
  local file = assert(io.open(path, "rb"))
  local got = file:read("a")

  file:close()
  assert(got == content, ("%s: got %s"):format(what, vim.inspect(got)))
end

T["ordered pipelines run every step and write the result"] = function()
  local bufnr = case("order", { "hello world" }, {
    { "tr", "a-z", "A-Z" },
    { "sed", "s/HELLO/BONJOUR/" },
  })

  write(bufnr, dir .. "/order.txt")
  assert_lines(bufnr, { "BONJOUR WORLD" }, "steps apply in order")
  assert_file(
    dir .. "/order.txt",
    "BONJOUR WORLD\n",
    "the written file matches the buffer"
  )
end

T["a failing formatter does not block or modify a save"] = function()
  local bufnr = case("failure", { "keep me" }, { "false" })

  write(bufnr, dir .. "/failure.txt")
  assert_lines(
    bufnr,
    { "keep me" },
    "a failing formatter leaves the buffer alone"
  )
  assert_file(
    dir .. "/failure.txt",
    "keep me\n",
    "a failing formatter does not block the save"
  )
end

T["pipeline failure is atomic"] = function()
  local bufnr = case("atomic", { "keep lowercase" }, {
    { "tr", "a-z", "A-Z" },
    "false",
  })

  write(bufnr, dir .. "/atomic.txt")
  assert_lines(bufnr, { "keep lowercase" }, "a pipeline failure is atomic")
  assert_file(
    dir .. "/atomic.txt",
    "keep lowercase\n",
    "atomic failure still saves"
  )
end

T["a process killed by a signal fails"] = function()
  local bufnr = case("signal", { "original" }, {
    { "sh", "-c", "printf PARTIAL; kill -TERM $$" },
  })

  write(bufnr, dir .. "/signal.txt")
  assert_lines(bufnr, { "original" }, "signal output is rejected")
  assert_file(dir .. "/signal.txt", "original\n", "signal failure still saves")
end

T["an uninstalled formatter is skipped"] = function()
  local bufnr = case("missing", { "abc" }, {
    "poincare-no-such-formatter",
    { "tr", "a-z", "A-Z" },
  })

  write(bufnr, dir .. "/missing.txt")
  assert_lines(bufnr, { "ABC" }, "only installed formatters run")
end

T["empty formatter output does not wipe the buffer"] = function()
  local bufnr = case("wipe", { "data" }, { "true" })

  write(bufnr, dir .. "/wipe.txt")
  assert_lines(bufnr, { "data" }, "empty output is not applied")
  assert_file(
    dir .. "/wipe.txt",
    "data\n",
    "empty output does not block the save"
  )
end

T["NUL formatter output is rejected"] = function()
  local bufnr = case("nul", { "text" }, {
    { "sh", "-c", "printf '\\0'" },
  })

  write(bufnr, dir .. "/nul.txt")
  assert_lines(bufnr, { "text" }, "NUL output is rejected")
  assert_file(dir .. "/nul.txt", "text\n", "NUL output does not block the save")
end

T["a hung formatter is killed within the shared budget"] = function()
  local bufnr = case("slow", { "still here" }, {
    { "sh", "-c", "sleep 0.65; tr a-z A-Z" },
    { "sleep", "3" },
  })
  local notification
  local notify = vim.notify

  vim.notify = function(message)
    notification = message
  end
  local started = vim.uv.hrtime()
  local ok, err = pcall(write, bufnr, dir .. "/slow.txt")
  local elapsed = (vim.uv.hrtime() - started) / 1e9

  vim.notify = notify
  assert(ok, err)
  assert(elapsed < 1.5, ("shared timeout took %.3fs"):format(elapsed))
  assert(
    notification == 'formatter "sleep" failed: timed out',
    "timeout did not report the active formatter"
  )
  assert_lines(
    bufnr,
    { "still here" },
    "a timed-out formatter leaves the buffer alone"
  )
  assert_file(
    dir .. "/slow.txt",
    "still here\n",
    "a timed-out formatter does not block the save"
  )
end

T["re-registering replaces or clears a filetype rule"] = function()
  local bufnr = case("disabled", { "lowercase" }, { { "tr", "a-z", "A-Z" } })

  register({ filetypes = { "disabled" } }, {})
  write(bufnr, dir .. "/disabled.txt")
  assert_lines(bufnr, { "lowercase" }, "empty registration disables formatting")

  register({ filetypes = { "disabled" } }, { "poincare-no-such-formatter" })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "still lowercase" })
  write(bufnr, dir .. "/disabled-missing.txt")
  assert_lines(
    bufnr,
    { "still lowercase" },
    "all-missing registration disables formatting"
  )
end

T["argv is copied and filenames bypass shell interpolation"] = function()
  local path = dir .. "/name with spaces.txt"
  local spec = {
    {
      "sh",
      "-c",
      'test "$1" = "$2" && cat',
      "formatter",
      path,
      "$FILENAME",
    },
  }
  local original = vim.deepcopy(spec)
  local bufnr = case("filename", { "safe name" }, spec)

  write(bufnr, path)
  assert(vim.deep_equal(spec, original), "registration mutated argv")
  assert_lines(bufnr, { "safe name" }, "a spaced filename is passed verbatim")
end

T["map and sparse formatter configurations are rejected"] = function()
  local invalid = {
    {
      name = "map top-level spec",
      lang = { filetypes = { "invalid-spec-map" } },
      spec = { formatter = "cat" },
    },
    {
      name = "sparse top-level spec",
      lang = { filetypes = { "invalid-spec-sparse" } },
      spec = { [1] = "cat", [3] = "cat" },
    },
    {
      name = "map argv",
      lang = { filetypes = { "invalid-argv-map" } },
      spec = { { "cat", ignored = "argument" } },
    },
    {
      name = "sparse argv",
      lang = { filetypes = { "invalid-argv-sparse" } },
      spec = { { [1] = "cat", [3] = "argument" } },
    },
    {
      name = "map filetypes",
      lang = { filetypes = { named = "invalid-filetype-map" } },
      spec = "cat",
    },
    {
      name = "sparse filetypes",
      lang = {
        filetypes = {
          [1] = "invalid-filetype-sparse-first",
          [3] = "invalid-filetype-sparse-third",
        },
      },
      spec = "cat",
    },
  }

  for _, configuration in ipairs(invalid) do
    local ok = pcall(register, configuration.lang, configuration.spec)

    assert(not ok, configuration.name .. " was accepted")
  end
end

T["diff hunks preserve positions and form one undo step"] = function()
  local before = { "alpha", "bravo", "change", "delta", "echo" }
  local path = dir .. "/diff.txt"

  assert(vim.fn.writefile(before, path) == 0)
  vim.cmd.edit(vim.fn.fnameescape(path))
  local bufnr = vim.api.nvim_get_current_buf()

  vim.bo[bufnr].filetype = "diff"
  register({ filetypes = { "diff" } }, {
    {
      "sed",
      "-e",
      "1i inserted",
      "-e",
      "s/change/CHANGED/",
      "-e",
      "/bravo/d",
      "-e",
      "$a appended",
    },
  })
  local namespace = vim.api.nvim_create_namespace("formatters-test")

  vim.api.nvim_set_current_buf(bufnr)
  local first = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(first, { 4, 2 })
  vim.api.nvim_buf_set_mark(bufnr, "a", 4, 2, {})
  local extmark = vim.api.nvim_buf_set_extmark(bufnr, namespace, 3, 2, {})
  vim.api.nvim_buf_set_mark(bufnr, "b", 5, 1, {})
  local eof_extmark = vim.api.nvim_buf_set_extmark(bufnr, namespace, 4, 1, {})
  vim.cmd("split")
  local second = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(second, { 5, 1 })

  write(bufnr, path)
  assert_lines(
    bufnr,
    { "inserted", "alpha", "CHANGED", "delta", "echo", "appended" },
    "insert/delete/replace/EOF hunks apply"
  )
  assert(
    vim.deep_equal(vim.api.nvim_win_get_cursor(first), { 4, 2 }),
    "first cursor moved"
  )
  assert(
    vim.deep_equal(vim.api.nvim_win_get_cursor(second), { 5, 1 }),
    "second cursor moved"
  )
  assert(
    vim.deep_equal(vim.api.nvim_buf_get_mark(bufnr, "a"), { 4, 2 }),
    "mark moved"
  )
  assert(
    vim.deep_equal(
      vim.api.nvim_buf_get_extmark_by_id(bufnr, namespace, extmark, {}),
      { 3, 2 }
    ),
    "extmark moved"
  )
  assert(
    vim.deep_equal(vim.api.nvim_buf_get_mark(bufnr, "b"), { 5, 1 }),
    "old last-line mark moved"
  )
  assert(
    vim.deep_equal(
      vim.api.nvim_buf_get_extmark_by_id(bufnr, namespace, eof_extmark, {}),
      { 4, 1 }
    ),
    "old last-line extmark moved"
  )

  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("silent undo")
  end)
  assert_lines(bufnr, before, "all format hunks undo together")
  vim.api.nvim_win_close(second, true)
end

T["formatter output can insert and delete trailing empty lines"] = function()
  local deleted = case("trailing-delete", { "alpha", "" }, { { "sed", "$d" } })

  vim.api.nvim_exec_autocmds("BufWritePre", { buffer = deleted })
  assert_lines(deleted, { "alpha" }, "trailing empty line is deleted")

  local inserted = case("trailing-insert", { "alpha" }, {
    { "sh", "-c", 'cat; printf "\\n"' },
  })

  vim.api.nvim_exec_autocmds("BufWritePre", { buffer = inserted })
  assert_lines(inserted, { "alpha", "" }, "trailing empty line is inserted")
end

T["an insertion moves the cursor and viewport with unchanged text"] = function()
  local bufnr = case(
    "insert",
    { "alpha", "bravo", "charlie", "delta", "echo" },
    {
      { "sed", "1i inserted" },
    }
  )

  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_win_set_height(0, 3)
  vim.api.nvim_win_set_cursor(0, { 4, 2 })
  vim.cmd("normal! zt")
  local view = vim.fn.winsaveview()
  local top =
    vim.api.nvim_buf_get_lines(bufnr, view.topline - 1, view.topline, false)[1]

  write(bufnr, dir .. "/insert.txt")
  assert(
    vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 5, 2 }),
    "cursor did not follow inserted text"
  )
  local new_view = vim.fn.winsaveview()

  assert(
    vim.api.nvim_buf_get_lines(
      bufnr,
      new_view.topline - 1,
      new_view.topline,
      false
    )[1] == top,
    "viewport did not follow inserted text"
  )
end

T["a blank buffer stays blank and writes an empty file"] = function()
  local bufnr = case("blank", nil, { { "tr", "a-z", "A-Z" } })

  write(bufnr, dir .. "/blank.txt")
  assert_lines(bufnr, { "" }, "a blank buffer stays blank")
  assert_file(dir .. "/blank.txt", "", "a blank buffer writes an empty file")
end

T["a missing final newline is preserved"] = function()
  local bufnr = case(
    "noeol",
    { "no final newline" },
    { { "tr", "a-z", "A-Z" } }
  )

  vim.bo[bufnr].endofline = false
  vim.bo[bufnr].fixendofline = false
  write(bufnr, dir .. "/noeol.txt")
  assert_lines(
    bufnr,
    { "NO FINAL NEWLINE" },
    "a noendofline buffer is still formatted"
  )
  assert_file(
    dir .. "/noeol.txt",
    "NO FINAL NEWLINE",
    "the missing final newline survives"
  )
end

T["a no-op formatter leaves the buffer untouched"] = function()
  local bufnr = case("noop", { "as you were" }, { "cat" })
  local path = dir .. "/noop.txt"

  vim.api.nvim_buf_set_name(bufnr, path)
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local sequence = vim.api.nvim_buf_call(bufnr, function()
    return vim.fn.undotree().seq_cur
  end)

  vim.api.nvim_exec_autocmds("BufWritePre", { buffer = bufnr })
  assert_lines(bufnr, { "as you were" }, "a no-op formatter changes nothing")
  assert(
    vim.api.nvim_buf_get_changedtick(bufnr) == tick,
    "a no-op changed the buffer"
  )
  assert(vim.api.nvim_buf_call(bufnr, function()
    return vim.fn.undotree().seq_cur
  end) == sequence, "a no-op created an undo entry")
  write(bufnr, path)
  assert_file(
    path,
    "as you were\n",
    "a no-op formatter does not block the save"
  )
end

T["fileformat remains a buffer concern"] = function()
  local bufnr = case("crlf", { "lower", "case" }, { { "tr", "a-z", "A-Z" } })

  vim.bo[bufnr].fileformat = "dos"
  write(bufnr, dir .. "/crlf.txt")
  assert_lines(bufnr, { "LOWER", "CASE" }, "CRLF content is formatted")
  assert_file(
    dir .. "/crlf.txt",
    "LOWER\r\nCASE\r\n",
    "CRLF is preserved on disk"
  )
end

T["concurrent edits win and window changes remain safe"] = function()
  local bufnr = case("race", { "original" }, {
    { "sh", "-c", "sleep 0.2; tr a-z A-Z" },
  })
  local other = vim.api.nvim_create_buf(true, false)
  local fired = false

  vim.api.nvim_set_current_buf(bufnr)
  vim.defer_fn(function()
    fired = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "deferred edit" })
    vim.api.nvim_set_current_buf(other)
  end, 20)
  vim.v.errmsg = ""
  local ok, err =
    pcall(vim.api.nvim_exec_autocmds, "BufWritePre", { buffer = bufnr })

  assert(ok, err)
  assert(fired, "deferred edit did not run while the formatter was pending")
  assert(vim.v.errmsg == "", "race raised a callback error: " .. vim.v.errmsg)
  assert_lines(
    bufnr,
    { "deferred edit" },
    "concurrent edits are not overwritten"
  )
  assert(
    vim.api.nvim_get_current_buf() == other,
    "formatting switched the current buffer"
  )
end

T["recursive write events do not start another run"] = function()
  local bufnr = case("nested", { "once" }, {
    { "sh", "-c", "sleep 0.25; sed 's/$/ formatted/'" },
  })
  local fired = false

  vim.defer_fn(function()
    fired = true
    vim.api.nvim_exec_autocmds("BufWritePre", { buffer = bufnr })
  end, 20)
  local started = vim.uv.hrtime()

  vim.v.errmsg = ""
  local ok, err =
    pcall(vim.api.nvim_exec_autocmds, "BufWritePre", { buffer = bufnr })
  local elapsed = (vim.uv.hrtime() - started) / 1e9

  assert(ok, err)
  assert(
    fired,
    "recursive write event did not run while formatting was pending"
  )
  assert(
    vim.v.errmsg == "",
    "nested formatting raised a callback error: " .. vim.v.errmsg
  )
  assert(elapsed < 0.75, ("nested formatting took %.3fs"):format(elapsed))
  assert_lines(bufnr, { "once formatted" }, "nested formatting runs once")
end

T["a hidden target uses its own undo history"] = function()
  local current = vim.api.nvim_create_buf(true, false)

  vim.api.nvim_set_current_buf(current)
  local current_window = vim.api.nvim_get_current_win()
  vim.cmd("normal! iinitial")
  vim.cmd("let &undolevels = &undolevels")
  vim.cmd("normal! A more")
  vim.cmd("silent undo")
  local current_sequence = vim.fn.undotree().seq_cur
  local target_before = { "one", "same", "three", "last" }
  local target = case("hidden", target_before, {
    { "sed", "-e", "s/one/ONE/", "-e", "s/three/THREE/" },
  })
  local notifications = {}
  local notify = vim.notify

  vim.api.nvim_buf_call(target, function()
    vim.cmd("let &undolevels = &undolevels")
  end)
  vim.notify = function(message, level)
    notifications[#notifications + 1] = { message, level }
  end
  vim.v.errmsg = ""
  local ok, err =
    pcall(vim.api.nvim_exec_autocmds, "BufWritePre", { buffer = target })
  vim.notify = notify

  assert(ok, err)
  assert(vim.v.errmsg == "", "hidden formatting error: " .. vim.v.errmsg)
  assert(#notifications == 0, "hidden formatting emitted a notification")
  assert_lines(target, { "ONE", "same", "THREE", "last" }, "hidden target")
  assert(vim.api.nvim_get_current_buf() == current, "current buffer changed")
  assert(
    vim.api.nvim_get_current_win() == current_window,
    "current window changed"
  )
  assert_lines(current, { "initial" }, "current buffer changed")
  assert(vim.fn.undotree().seq_cur == current_sequence, "current undo changed")
  vim.api.nvim_buf_call(target, function()
    vim.cmd("silent undo")
  end)
  assert_lines(target, target_before, "hidden target format undoes once")
end

T["Lua spec configures StyLua for stdin"] = function()
  if vim.fn.executable("stylua") ~= 1 then
    MiniTest.skip("stylua is not installed")
  end

  local bufnr = case("lua", { "local x  =   1" }, lua_spec.formatters)

  write(bufnr, dir .. "/real.lua")
  assert_lines(
    bufnr,
    { "local x = 1" },
    "the Lua formatter command formats through stdin"
  )
  assert_file(dir .. "/real.lua", "local x = 1\n", "stylua output is written")
end

T["alejandra runs bare on stdin"] = function()
  if vim.fn.executable("alejandra") ~= 1 then
    MiniTest.skip("alejandra is not installed")
  end

  local bufnr = case("nix", { "let", "  x=1;", "in x" }, "alejandra")

  write(bufnr, dir .. "/real.nix")
  assert_lines(
    bufnr,
    { "let", "  x = 1;", "in", "  x" },
    "alejandra formats stdin"
  )
end

return T
