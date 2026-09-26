local T = require("mini.test").new_set()
local git = dofile("tests/regressions/git.lua")

T["a failed VC query does not retrigger solely by statusline redraw"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp(
      (vim.env.TMPDIR or "/tmp") .. "/poincare-vc-failure-XXXXXX"
    )
  )
  local repo = dir .. "/repo"
  local original_system = vim.system
  local original_statusline = vim.o.statusline
  local calls, failures = 0, 0

  local ok, err = xpcall(function()
    vim.fn.mkdir(repo .. "/.git", "p") -- Detected as a Git root; not a usable Git directory.
    git.write(repo .. "/A", "content\n")
    local probe = assert(
      original_system(
        { "git", "-C", repo, "status", "--porcelain=v2", "--branch" },
        { text = true }
      ):wait(3000)
    )
    assert(probe.code ~= 0, "incomplete .git unexpectedly accepted by real Git")
    assert(
      original_statusline:find("render", 1, true),
      "configured statusline was not installed"
    )

    vim.system = function(args, opts, callback)
      if
        args[1] == "git"
        and args[2] == "-C"
        and args[3] == repo
        and args[4] == "status"
        and callback
      then
        calls = calls + 1
        if calls >= 3 then
          vim.o.statusline = "" -- Stop the cycle before another redraw can spawn work.
        end
        return original_system(args, opts, function(result)
          if result.code ~= 0 then
            failures = failures + 1
          end
          callback(result)
        end)
      end
      return original_system(args, opts, callback)
    end

    vim.cmd.edit(vim.fn.fnameescape(repo .. "/A"))
    vim.cmd.redraw()
    assert(
      vim.wait(3000, function()
        return failures >= 1
      end, 20),
      "real Git failure callback did not arrive"
    )
    -- No further edit, refresh, focus event, or manually invoked component.
    vim.wait(400, function()
      return calls >= 3
    end, 20)
    vim.o.statusline = "" -- Also stop when a corrected implementation does not retry.
    assert(failures >= 1, "statusline query did not fail")
    assert(
      calls <= 1,
      ("failure-triggered redraw spawned %d Git queries"):format(calls)
    )
  end, debug.traceback)

  vim.o.statusline = ""
  vim.cmd.enew({ bang = true })
  vim.system = original_system
  vim.o.statusline = original_statusline
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

return T
