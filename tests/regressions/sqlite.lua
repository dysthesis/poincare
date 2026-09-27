local T = require("mini.test").new_set()

local function sqlite(path, statement)
  local result = assert(
    vim.system({ "sqlite3", path, statement }, { text = true }):wait(3000)
  )
  assert(result.code == 0, ("sqlite3 %s: %s"):format(path, result.stderr or ""))
  return vim.trim(result.stdout or "")
end

T["SQLiteUse targets the exact percent-bearing filesystem path"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp((vim.env.TMPDIR or "/tmp") .. "/poincare-sqlite-XXXXXX")
  )
  local previous = vim.fn.getcwd()
  local literal = dir .. "/data%20copy.db"
  local space = dir .. "/data copy.db"
  local plain = dir .. "/plain.db"

  local ok, err = xpcall(function()
    vim.fn.chdir(dir)
    for _, entry in ipairs({
      { plain, "PLAIN" },
      { literal, "LITERAL" },
      { space, "SPACE" },
    }) do
      sqlite(
        entry[1],
        "CREATE TABLE sample(value TEXT); INSERT INTO sample VALUES('"
          .. entry[2]
          .. "');"
      )
      assert(
        sqlite(entry[1], "SELECT value FROM sample;") == entry[2],
        "fixture is not independent"
      )
    end

    vim.cmd.edit(vim.fn.fnameescape(dir .. "/query.sql"))
    vim.api.nvim_buf_set_lines(
      0,
      0,
      -1,
      false,
      { "UPDATE sample SET value='UPDATED_BY_DB';" }
    )
    vim.cmd("SQLiteUse " .. vim.fn.fnameescape(literal))
    assert(vim.b.db and vim.b.db ~= "", "SQLiteUse did not set a database")
    vim.cmd("%DB")

    local completed = vim.wait(3000, function()
      return sqlite(literal, "SELECT value FROM sample;") == "UPDATED_BY_DB"
        or sqlite(space, "SELECT value FROM sample;") == "UPDATED_BY_DB"
    end, 30)
    assert(
      completed,
      "Dadbod query did not update either database within 3 seconds"
    )

    local got_literal = sqlite(literal, "SELECT value FROM sample;")
    local got_space = sqlite(space, "SELECT value FROM sample;")
    assert(
      got_literal == "UPDATED_BY_DB" and got_space == "SPACE",
      ("wrong target: literal=%s, space=%s"):format(got_literal, got_space)
    )
    assert(
      sqlite(plain, "SELECT value FROM sample;") == "PLAIN",
      "plain control database was changed"
    )
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
    vim.api.nvim_buf_set_lines(
      0,
      0,
      -1,
      false,
      { "UPDATE sample SET value='UPDATED_BY_DB';" }
    )
    vim.cmd("SQLiteUse " .. vim.fn.fnameescape(literal))
    vim.cmd("%DB")

    assert(
      vim.wait(3000, function()
        return sqlite(literal, "SELECT value FROM sample;") == "UPDATED_BY_DB"
      end, 30),
      "Dadbod did not update the database at the literal reserved-byte path"
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

return T
