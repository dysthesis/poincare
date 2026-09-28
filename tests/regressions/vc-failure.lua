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
    -- A settled failure is silent until an ordinary refresh, not a redraw.
    assert(failures >= 1, "statusline query did not fail")
    assert(
      calls <= 1,
      ("failure-triggered redraw spawned %d Git queries"):format(calls)
    )
    vim.fn.delete(repo .. "/.git", "rf")
    git.run(repo, "init", "-q", "-b", "recovered-probe")
    git.run(repo, "add", "A")
    assert(
      git
        .run(repo, "status", "--porcelain=v2", "--branch")
        :find("# branch.head recovered-probe", 1, true),
      "repaired Git backend is not usable"
    )
    local buf = vim.api.nvim_get_current_buf()
    require("ui.statusline.vc").refresh(buf)
    local rendered
    assert(
      vim.wait(3000, function()
        rendered = vim.api.nvim_eval_statusline(vim.o.statusline, {
          winid = vim.api.nvim_get_current_win(),
        }).str
        return rendered:find("recovered-probe", 1, true) ~= nil
      end, 20),
      "normal refresh did not recover the real Git branch"
    )
    assert(
      calls == 2 and failures == 1,
      ("repair launched %d queries with %d failures"):format(calls, failures)
    )
  end, debug.traceback)

  vim.o.statusline = ""
  vim.cmd.enew({ bang = true })
  vim.system = original_system
  vim.o.statusline = original_statusline
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

T["renaming a buffer outside Git removes its VC status immediately"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp(
      (vim.env.TMPDIR or "/tmp") .. "/poincare-vc-rename-XXXXXX"
    )
  )
  local repo, outside = dir .. "/repo", dir .. "/outside"

  local ok, err = xpcall(function()
    vim.fn.mkdir(repo, "p")
    vim.fn.mkdir(outside, "p")
    git.run(repo, "init", "-q", "-b", "rename-probe")
    git.write(repo .. "/A", "tracked\n")
    git.run(repo, "add", "A")
    assert(
      git
        .run(repo, "status", "--porcelain=v2", "--branch")
        :find("# branch.head rename-probe", 1, true),
      "real Git branch oracle is wrong"
    )

    vim.cmd.edit(vim.fn.fnameescape(repo .. "/A"))
    local buf = vim.api.nvim_get_current_buf()
    local vc = require("ui.statusline.vc")
    assert(
      vim.wait(3000, function()
        return vc.component():find("rename-probe", 1, true) ~= nil
      end, 20),
      "real Git branch did not reach the statusline"
    )

    local renamed = outside .. "/B"
    vim.cmd.file(vim.fn.fnameescape(renamed))
    assert(vim.api.nvim_get_current_buf() == buf, "rename changed buffers")
    assert(vim.api.nvim_buf_get_name(buf) == renamed, "rename did not stick")
    assert(vim.fs.root(buf, ".git") == nil, "destination is inside Git")
    vim.cmd.redrawstatus()
    local rendered = vim.api.nvim_eval_statusline(vim.o.statusline, {
      winid = vim.api.nvim_get_current_win(),
    }).str
    assert(vc.component() == "", "renamed buffer retained its old VC component")
    assert(
      not rendered:find("rename-probe", 1, true),
      "renamed buffer still displays its old Git branch"
    )
  end, debug.traceback)

  vim.cmd.enew({ bang = true })
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

T["a write during an in-flight VC query eventually displays the new status"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp(
      (vim.env.TMPDIR or "/tmp") .. "/poincare-vc-overlap-XXXXXX"
    )
  )
  local repo = dir .. "/repo"
  local original_system = vim.system

  local ok, err = xpcall(function()
    vim.fn.mkdir(repo, "p")
    git.run(repo, "init", "-q", "-b", "overlap-probe")
    git.write(repo .. "/A", "before\n")
    git.run(repo, "add", "A")
    git.run(
      repo,
      "-c",
      "user.name=Probe",
      "-c",
      "user.email=probe@example.invalid",
      "commit",
      "-qm",
      "initial"
    )
    local clean = git.run(repo, "status", "--porcelain=v2", "--branch")
    assert(
      clean:find("# branch.head overlap-probe", 1, true)
        and not clean:find("1 .M", 1, true),
      "initial Git status was not clean"
    )

    local calls, held, release = 0
    vim.system = function(args, opts, callback)
      if
        args[1] == "git"
        and args[2] == "-C"
        and args[3] == repo
        and args[4] == "status"
        and callback
      then
        calls = calls + 1
        if calls == 1 then
          return original_system(args, opts, function(result)
            held = result
            release = function()
              callback(result)
            end
          end)
        end
      end
      return original_system(args, opts, callback)
    end

    vim.cmd.edit(vim.fn.fnameescape(repo .. "/A"))
    local buf = vim.api.nvim_get_current_buf()
    local vc = require("ui.statusline.vc")
    if calls == 0 then
      vc.refresh(buf)
    end
    assert(
      vim.wait(3000, function()
        return held ~= nil
      end, 20),
      "real clean Git result did not finish"
    )
    assert(held.code == 0 and held.stdout == clean, "held result was not clean")
    assert(calls == 1, "unexpected initial query count")

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "after" })
    vim.cmd.write()
    local dirty = git.run(repo, "status", "--porcelain=v2", "--branch")
    assert(
      dirty:find("1 .M", 1, true)
        and git.read(repo .. "/A") == "after\n"
        and git.run(repo, "show", ":A") == "before\n",
      "write did not produce a real dirty repository"
    )
    assert(calls == 1, "overlapping write started a redundant query")

    release()
    assert(
      vim.wait(3000, function()
        return calls == 2
          and vc.component():find("overlap-probe", 1, true) ~= nil
          and vc.component():find(" ±", 1, true) ~= nil
      end, 20),
      "coalesced write did not publish the newer dirty status"
    )
  end, debug.traceback)

  vim.system = original_system
  vim.cmd.enew({ bang = true })
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

return T
