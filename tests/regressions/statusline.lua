local T = require("mini.test").new_set()

T["filename is inert when the active statusline is evaluated"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp(
      (vim.env.TMPDIR or "/tmp") .. "/poincare-statusline-XXXXXX"
    )
  )
  local previous = vim.fn.getcwd()
  local name = '%{writefile(["safe-marker"],"actual-marker")}'

  local ok, err = xpcall(function()
    vim.fn.chdir(dir)
    assert(vim.fn.writefile({ "plain" }, dir .. "/plain.txt") == 0)
    assert(vim.fn.writefile({ "payload" }, dir .. "/" .. name) == 0)

    local function display(filename)
      vim.cmd.edit(vim.fn.fnameescape(dir .. "/" .. filename))
      vim.cmd.redrawstatus()
      return vim.api.nvim_eval_statusline(vim.o.statusline, {
        winid = vim.api.nvim_get_current_win(),
      }).str
    end

    assert(
      display("plain.txt"):find("plain.txt", 1, true),
      "control filename was not displayed"
    )
    assert(
      vim.fn.filereadable(dir .. "/actual-marker") == 0,
      "control created the marker"
    )
    local rendered = display(name)
    assert(
      vim.fn.filereadable(dir .. "/actual-marker") == 0,
      "display executed the filename"
    )
    assert(
      rendered:find(name, 1, true),
      "the filename was not displayed literally: " .. rendered
    )
  end, debug.traceback)

  vim.cmd.enew({ bang = true })
  vim.fn.chdir(previous)
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

return T
