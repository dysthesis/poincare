local T = require("mini.test").new_set()
local git = dofile("tests/regressions/git.lua")

T["saveas outside Git removes signs from the same buffer"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp((vim.env.TMPDIR or "/tmp") .. "/poincare-saveas-XXXXXX")
  )
  local repo, outside = dir .. "/repo", dir .. "/out"
  local original_system = vim.system
  local pending = 0

  local ok, err = xpcall(function()
    vim.fn.mkdir(repo, "p")
    vim.fn.mkdir(outside, "p")
    git.run(repo, "init", "-q")
    git.write(repo .. "/A", "old\n")
    git.run(repo, "add", "A")
    assert(git.run(repo, "show", ":A") == "old\n", "index oracle is wrong")
    git.write(repo .. "/A", "changed\n")

    vim.system = function(args, opts, callback)
      if
        args[1] == "git"
        and args[2] == "show"
        and args[3] == ":A"
        and callback
      then
        pending = pending + 1
        return original_system(args, opts, function(result)
          pending = pending - 1
          callback(result)
        end)
      end
      return original_system(args, opts, callback)
    end

    vim.cmd.edit(vim.fn.fnameescape(repo .. "/A"))
    local buf = vim.api.nvim_get_current_buf()
    assert(
      vim.wait(3000, function()
        return pending == 0
          and vim.deep_equal(git.signs(buf), { "GitGutterChange" })
      end, 20),
      "tracked changed file did not get a settled change sign"
    )

    local b = outside .. "/B"
    vim.cmd("saveas " .. vim.fn.fnameescape(b))
    assert(
      vim.api.nvim_get_current_buf() == buf,
      "saveas changed buffer identity"
    )
    assert(
      vim.fs.root(b, ".git") == nil,
      "destination unexpectedly belongs to Git"
    )
    assert(git.read(b) == "changed\n", "saveas bytes differ from working text")
    local after_saveas = git.signs(buf)

    vim.cmd.enew({ bang = true })
    vim.cmd.edit(vim.fn.fnameescape(b))
    local after_reentry = git.signs(vim.api.nvim_get_current_buf())
    local c = outside .. "/C"
    git.write(c, "changed\n")
    vim.cmd.edit(vim.fn.fnameescape(c))
    assert(
      #git.signs(vim.api.nvim_get_current_buf()) == 0,
      "fresh outside control got signs"
    )
    assert(
      #after_saveas == 0,
      "saveas left stale index signs: " .. vim.inspect(after_saveas)
    )
    assert(#after_reentry == 0, "reentering outside file retained old signs")
  end, debug.traceback)

  vim.system = original_system
  vim.cmd.enew({ bang = true })
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

return T
