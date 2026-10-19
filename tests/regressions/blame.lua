local T = require("mini.test").new_set()
local git = dofile("tests/regressions/git.lua")
local ns = assert(vim.api.nvim_get_namespaces().git_blame)

local function display(buf)
  local mark = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {
    details = true,
  })[1]
  if not mark then
    return ""
  end
  local chunks = {}
  for _, chunk in ipairs(mark[4].virt_text) do
    chunks[#chunks + 1] = chunk[1]
  end
  return table.concat(chunks), mark[2]
end

local function wait_for_commit(buf, hash, row)
  assert(
    vim.wait(3000, function()
      local text, marked_row = display(buf)
      return marked_row == row and text:find(hash, 1, true) ~= nil
    end, 10),
    "expected commit " .. hash .. " on row " .. row .. ": " .. display(buf)
  )
end

local function wait_for_uncommitted(fixture)
  assert(
    vim.wait(3000, function()
      local text = display(fixture.buf)
      return text ~= ""
        and not text:find(fixture.first, 1, true)
        and not text:find(fixture.second, 1, true)
        and not text:find("00000000", 1, true)
    end, 10),
    "uncommitted line retained commit metadata: " .. display(fixture.buf)
  )
end

local function flush()
  local done = false
  vim.schedule(function()
    done = true
  end)
  assert(
    vim.wait(1000, function()
      return done
    end, 10),
    "scheduled blame callback did not finish"
  )
end

local function with_repo(callback)
  local root = assert(
    vim.uv.fs_mkdtemp((vim.env.TMPDIR or "/tmp") .. "/poincare-blame-XXXXXX")
  )
  local original_system = vim.system
  local ok, err = xpcall(function()
    git.run(root, "init", "-q")
    git.run(root, "config", "user.name", "Blame Author")
    git.run(root, "config", "user.email", "blame@example.invalid")
    git.run(root, "config", "commit.gpgsign", "false")
    local path = root .. "/file with spaces.txt"
    git.write(path, "alpha\nbeta\n")
    git.run(root, "add", ".")
    git.run(root, "commit", "-qm", "Initial lines")
    local first = vim.trim(git.run(root, "rev-parse", "HEAD")):sub(1, 8)
    git.write(path, "alpha\nbravo\n")
    git.run(root, "commit", "-qam", "Update second line")
    local second = vim.trim(git.run(root, "rev-parse", "HEAD")):sub(1, 8)
    vim.cmd.edit(vim.fn.fnameescape(path))
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    require("ui.blame").blame_line()
    wait_for_commit(buf, first, 0)
    callback({
      root = root,
      path = path,
      buf = buf,
      first = first,
      second = second,
      system = original_system,
    })
  end, debug.traceback)
  vim.system = original_system
  vim.cmd.enew({ bang = true })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local path = vim.api.nvim_buf_get_name(buf)
    if vim.startswith(path, root .. "/") or path == root .. "-outside.txt" then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  vim.fn.delete(root, "rf")
  assert(ok, err)
end

local function hold_blame(fixture)
  local held = {}
  vim.system = function(args, opts, callback)
    if args[1] == "git" and args[2] == "blame" and callback then
      return fixture.system(args, opts, function(result)
        held[#held + 1] = { callback = callback, result = result }
      end)
    end
    return fixture.system(args, opts, callback)
  end
  require("ui.blame").blame_line()
  assert(
    vim.wait(3000, function()
      return #held > 0
    end, 10),
    "real Git blame did not finish"
  )
  assert(held[1].result.code == 0, held[1].result.stderr)
  return held
end

T["unsaved edits and inserted lines use buffer contents without writing"] = function()
  with_repo(function(fixture)
    vim.api.nvim_buf_set_lines(fixture.buf, 0, 1, false, { "unsaved" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = fixture.buf })
    wait_for_uncommitted(fixture)

    vim.api.nvim_buf_set_lines(fixture.buf, 0, 0, false, { "inserted" })
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = fixture.buf })
    wait_for_commit(fixture.buf, fixture.second, 2)
    assert(git.read(fixture.path) == "alpha\nbravo\n", "blame wrote the buffer")
  end)
end

T["changed buffers reject completed old replies before TextChanged fires"] = function()
  with_repo(function(fixture)
    local held = hold_blame(fixture)
    local old = held[1]
    vim.api.nvim_buf_set_lines(fixture.buf, 0, 1, false, { "replacement" })
    old.callback(old.result)
    flush()
    assert(display(fixture.buf) == "", "old snapshot restored commit blame")

    vim.api.nvim_exec_autocmds("TextChanged", { buffer = fixture.buf })
    assert(
      vim.wait(3000, function()
        return #held >= 2
      end, 10),
      "updated real Git blame did not finish"
    )
    local latest = held[#held]
    assert(latest.result.code == 0, latest.result.stderr)
    assert(
      latest.result.stdout:match("^0+ "),
      "Git did not see the unsaved edit"
    )
    latest.callback(latest.result)
    wait_for_uncommitted(fixture)
    old.callback(old.result)
    flush()
    wait_for_uncommitted(fixture)
  end)
end

T["renaming the same buffer cannot publish blame for its previous path"] = function()
  with_repo(function(fixture)
    local old = hold_blame(fixture)[1]
    local outside = fixture.root .. "-outside.txt"
    vim.cmd.file(vim.fn.fnameescape(outside))
    assert(vim.api.nvim_get_current_buf() == fixture.buf)
    assert(vim.api.nvim_buf_get_name(fixture.buf) == outside)
    old.callback(old.result)
    flush()
    assert(
      display(fixture.buf) == "",
      "previous path restored its commit blame"
    )
  end)
end

T["an empty buffer is not confused with one uncommitted blank line"] = function()
  with_repo(function(fixture)
    vim.cmd('normal! gg"_dG')
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = fixture.buf })
    assert(vim.fn.wordcount().bytes == 0, "fixture is not empty")
    vim.wait(250, function()
      return false
    end, 10)
    assert(
      display(fixture.buf) == "",
      "empty buffer has a fictional blamed line"
    )

    git.write(fixture.path, "\n")
    vim.cmd.edit({ bang = true })
    assert(vim.fn.wordcount().bytes == 1, "fixture is not a single blank line")
    wait_for_uncommitted(fixture)
  end)
end

return T
