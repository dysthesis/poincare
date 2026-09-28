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

T["deleting and wiping a signed buffer clear its identity"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp((vim.env.TMPDIR or "/tmp") .. "/poincare-delete-XXXXXX")
  )
  local repo = dir .. "/repo"

  local ok, err = xpcall(function()
    vim.fn.mkdir(repo, "p")
    git.run(repo, "init", "-q")
    git.write(repo .. "/A", "indexed\n")
    git.run(repo, "add", "A")
    git.write(repo .. "/A", "working\n")
    vim.cmd.edit(vim.fn.fnameescape(repo .. "/A"))
    local buf = vim.api.nvim_get_current_buf()
    assert(
      vim.wait(3000, function()
        return vim.deep_equal(git.signs(buf), { "GitGutterChange" })
      end, 20),
      "signed buffer did not settle"
    )

    vim.cmd.bdelete({ buf, bang = true })
    assert(vim.api.nvim_buf_is_valid(buf), "bdelete wiped the buffer")
    assert(#git.signs(buf) == 0, "BufDelete left old extmarks")
    vim.cmd.bwipeout({ buf, bang = true })
    assert(not vim.api.nvim_buf_is_valid(buf), "bwipeout retained old buffer")
    assert(
      #git.signs(vim.api.nvim_get_current_buf()) == 0,
      "replacement buffer inherited old signs"
    )
  end, debug.traceback)

  vim.cmd.enew({ bang = true })
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

T["changing a signed file to nofile clears signs until it becomes eligible"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp((vim.env.TMPDIR or "/tmp") .. "/poincare-buftype-XXXXXX")
  )
  local repo = dir .. "/repo"

  local ok, err = xpcall(function()
    vim.fn.mkdir(repo, "p")
    git.run(repo, "init", "-q")
    git.write(repo .. "/A", "indexed\n")
    git.run(repo, "add", "A")
    assert(git.run(repo, "show", ":A") == "indexed\n")
    git.write(repo .. "/A", "working\n")
    vim.cmd.edit(vim.fn.fnameescape(repo .. "/A"))
    local buf = vim.api.nvim_get_current_buf()
    assert(
      vim.wait(3000, function()
        return vim.deep_equal(git.signs(buf), { "GitGutterChange" })
      end, 20),
      "real Git did not settle the original sign"
    )

    vim.cmd("setlocal buftype=nofile")
    assert(vim.bo[buf].buftype == "nofile")
    assert(#git.signs(buf) == 0, "ineligible buffer retained its settled sign")
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
    assert(#git.signs(buf) == 0, "ineligible render restored a sign")

    vim.cmd("setlocal buftype=")
    assert(vim.bo[buf].buftype == "")
    assert(
      vim.wait(3000, function()
        return vim.deep_equal(git.signs(buf), { "GitGutterChange" })
      end, 20),
      "eligible buffer did not refresh from real Git"
    )
    assert(git.read(repo .. "/A") == "working\n")
    assert(git.run(repo, "show", ":A") == "indexed\n")
  end, debug.traceback)

  vim.cmd.enew({ bang = true })
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

return T
