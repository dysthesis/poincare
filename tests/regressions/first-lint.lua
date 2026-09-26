local T = require("mini.test").new_set()

local function selene(buf)
  local result = {}
  for _, item in ipairs(vim.diagnostic.get(buf)) do
    if item.source == "selene" then
      result[#result + 1] = item
    end
  end
  return result
end

local cli = vim.env.POINCARE_TEST_CASE == "first_lint_cli"
T["first " .. (cli and "CLI argument" or "ordinary edit") .. " gets Selene diagnostics without a write"] = function()
  local dir = cli and "/work"
    or assert(
      vim.uv.fs_mkdtemp(
        (vim.env.TMPDIR or "/tmp") .. "/poincare-first-lint-XXXXXX"
      )
    )
  local previous = vim.fn.getcwd()

  local ok, err = xpcall(function()
    vim.fn.chdir(dir)
    assert(vim.fn.executable("selene") == 1, "real Selene is required")
    if cli then
      assert(
        vim.api.nvim_buf_get_name(0) == dir .. "/a.lua",
        "CLI file was not the initial buffer"
      )
      assert(
        vim.fn.filereadable(dir .. "/selene.toml") == 1,
        "missing startup Selene config"
      )
    else
      assert(
        package.loaded.lint == nil,
        "nvim-lint must be unloaded before first read"
      )
      assert(vim.fn.writefile({ 'std = "lua51"' }, dir .. "/selene.toml") == 0)
      local dirty = "print(undefined_variable)"
      assert(vim.fn.writefile({ dirty }, dir .. "/a.lua") == 0)
      assert(vim.fn.writefile({ dirty }, dir .. "/b.lua") == 0)
      vim.cmd.edit(vim.fn.fnameescape(dir .. "/a.lua"))
    end
    local first = vim.api.nvim_get_current_buf()
    assert(
      vim.bo[first].filetype == "lua",
      "normal filetype detection is required"
    )
    -- Snapshot before opening another file: later lazy-load events must not
    -- be able to retroactively satisfy this first-read assertion.
    local first_on_read = vim.wait(1200, function()
      return #selene(first) > 0
    end, 20)
    vim.cmd.edit(vim.fn.fnameescape(dir .. "/b.lua"))
    local second = vim.api.nvim_get_current_buf()
    assert(
      vim.bo[second].filetype == "lua",
      "control filetype detection failed"
    )
    assert(
      vim.wait(3000, function()
        return #selene(second) > 0
      end, 20),
      "second read did not produce a real Selene diagnostic"
    )

    vim.api.nvim_buf_set_lines(second, 0, -1, false, { 'print("ok")' })
    vim.cmd.write()
    assert(
      vim.wait(3000, function()
        return #selene(second) == 0
      end, 20),
      "clean write did not clear the second file's Selene diagnostic"
    )
    assert(
      first_on_read,
      "first file has no Selene diagnostic before second read or write"
    )
  end, debug.traceback)

  vim.cmd.enew({ bang = true })
  vim.fn.chdir(previous)
  if not cli then
    vim.fn.delete(dir, "rf")
  end
  assert(ok, err)
end

return T
