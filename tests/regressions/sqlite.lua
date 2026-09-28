local T = require("mini.test").new_set()

local function sqlite(path, statement)
  local result = assert(
    vim.system({ "sqlite3", path, statement }, { text = true }):wait(3000)
  )
  assert(result.code == 0, ("sqlite3 %s: %s"):format(path, result.stderr or ""))
  return vim.trim(result.stdout or "")
end

local function dadbod(buf, path, statement)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { statement })
  vim.cmd("SQLiteUse " .. vim.fn.fnameescape(path))
  assert(vim.b.db and vim.b.db ~= "", "SQLiteUse did not select a database")
  vim.cmd("%DB")
  local output =
    assert(vim.t.db_last_preview_buffer, "Dadbod did not open a result")
  assert(
    vim.wait(3000, function()
      local query = vim.b[output].db
      return query and query.exit_status ~= nil
    end, 20),
    "Dadbod query did not finish"
  )
  assert(vim.b[output].db.exit_status == 0, "Dadbod query failed")
  local lines = vim.api.nvim_buf_get_lines(output, 0, -1, false)
  return vim.trim(lines[#lines] or "")
end

T["SQLiteUse targets the exact percent-bearing filesystem path"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp((vim.env.TMPDIR or "/tmp") .. "/poincare-sqlite-XXXXXX")
  )
  local previous = vim.fn.getcwd()
  local literal = dir .. "/data%20copy.db"
  local space = dir .. "/data copy.db"
  local plain = dir .. "/plain.db"

  local entries = {
    { plain, "PLAIN" },
    { literal, "LITERAL" },
    { space, "SPACE" },
  }
  local values = {}

  local ok, err = xpcall(function()
    vim.fn.chdir(dir)
    for _, entry in ipairs(entries) do
      values[entry[1]] = entry[2]
      sqlite(
        entry[1],
        "CREATE TABLE sample(value TEXT); INSERT INTO sample VALUES('"
          .. entry[2]
          .. "');"
      )
      assert(sqlite(entry[1], "SELECT value FROM sample;") == entry[2])
    end

    vim.cmd.edit(vim.fn.fnameescape(dir .. "/query.sql"))
    local buf = vim.api.nvim_get_current_buf()
    for _, entry in ipairs(entries) do
      local path, value = unpack(entry)
      local selected = dadbod(buf, path, "SELECT value FROM sample;")
      assert(
        selected == value,
        ("Dadbod SELECT %s returned %q, expected %q"):format(
          path,
          selected,
          value
        )
      )
      local updated = "UPDATED_" .. value
      dadbod(buf, path, "UPDATE sample SET value='" .. updated .. "';")
      values[path] = updated
      for _, control in ipairs(entries) do
        local actual = sqlite(control[1], "SELECT value FROM sample;")
        assert(
          actual == values[control[1]],
          ("physical database %s contains %s, expected %s"):format(
            control[1],
            actual,
            values[control[1]]
          )
        )
      end
    end
  end, debug.traceback)

  vim.cmd.enew({ bang = true })
  vim.fn.chdir(previous)
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

T["SQLiteUse keeps URL delimiters, spaces and UTF-8 in the database path"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp((vim.env.TMPDIR or "/tmp") .. "/poincare-sqlite-XXXXXX")
  )
  local previous = vim.fn.getcwd()
  local literal = dir .. "/café ?#%@=&<> $.db"
  local control = dir .. "/control.db"

  local ok, err = xpcall(function()
    vim.fn.chdir(dir)
    for _, entry in ipairs({ { literal, "LITERAL" }, { control, "CONTROL" } }) do
      sqlite(
        entry[1],
        "CREATE TABLE sample(value TEXT); INSERT INTO sample VALUES('"
          .. entry[2]
          .. "');"
      )
    end

    vim.cmd.edit(vim.fn.fnameescape(dir .. "/query.sql"))
    local buf = vim.api.nvim_get_current_buf()
    local selected = dadbod(buf, literal, "SELECT value FROM sample;")
    assert(
      selected == "LITERAL",
      ("Dadbod SELECT reserved-byte path returned %q"):format(selected)
    )
    dadbod(buf, literal, "UPDATE sample SET value='UPDATED_BY_DB';")
    assert(
      sqlite(literal, "SELECT value FROM sample;") == "UPDATED_BY_DB",
      "Dadbod did not update the literal reserved-byte path"
    )
    assert(
      sqlite(control, "SELECT value FROM sample;") == "CONTROL",
      "unselected control database was changed"
    )
  end, debug.traceback)

  vim.cmd.enew({ bang = true })
  vim.fn.chdir(previous)
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

T["SQLiteUse distinguishes isolated question and hash path delimiters"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp((vim.env.TMPDIR or "/tmp") .. "/poincare-sqlite-XXXXXX")
  )
  local previous = vim.fn.getcwd()
  local entries = {
    { dir .. "/question?part.db", "QUESTION" },
    { dir .. "/hash#part.db", "HASH" },
    { dir .. "/question", "QUESTION_CONTROL" },
    { dir .. "/hash", "HASH_CONTROL" },
  }
  local values = {}

  local ok, err = xpcall(function()
    vim.fn.chdir(dir)
    for _, entry in ipairs(entries) do
      values[entry[1]] = entry[2]
      sqlite(
        entry[1],
        "CREATE TABLE sample(value TEXT); INSERT INTO sample VALUES('"
          .. entry[2]
          .. "');"
      )
    end
    vim.cmd.edit(vim.fn.fnameescape(dir .. "/query.sql"))
    local buf = vim.api.nvim_get_current_buf()
    for _, entry in ipairs({ entries[1], entries[2] }) do
      local path, value = unpack(entry)
      local selected = dadbod(buf, path, "SELECT value FROM sample;")
      assert(
        selected == value,
        ("Dadbod SELECT %s returned %q, expected %q"):format(
          path,
          selected,
          value
        )
      )
      values[path] = "UPDATED_" .. value
      dadbod(buf, path, "UPDATE sample SET value='" .. values[path] .. "';")
      for _, control in ipairs(entries) do
        assert(
          sqlite(control[1], "SELECT value FROM sample;") == values[control[1]],
          "wrong physical database after UPDATE: " .. control[1]
        )
      end
    end
  end, debug.traceback)

  vim.cmd.enew({ bang = true })
  vim.fn.chdir(previous)
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

return T
