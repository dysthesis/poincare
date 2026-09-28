local T = require("mini.test").new_set()
local git = dofile("tests/regressions/git.lua")

local function flush()
  local done = false
  vim.schedule(function()
    done = true
  end)
  assert(
    vim.wait(1000, function()
      return done
    end, 10),
    "scheduled gutter callback did not complete"
  )
end

T["older Git index result cannot restore signs after latest result"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp((vim.env.TMPDIR or "/tmp") .. "/poincare-race-XXXXXX")
  )
  local repo = dir .. "/repo"
  local held = {}
  local original_system = vim.system

  local ok, err = xpcall(function()
    vim.fn.mkdir(repo, "p")
    git.run(repo, "init", "-q")
    git.write(repo .. "/A", "old\n")
    git.run(repo, "add", "A")
    assert(
      git.run(repo, "show", ":A") == "old\n",
      "initial index oracle differs"
    )
    git.write(repo .. "/A", "new\n")

    vim.system = function(args, opts, callback)
      if
        args[1] == "git"
        and args[2] == "show"
        and args[3] == ":A"
        and callback
      then
        return original_system(args, opts, function(result)
          held[#held + 1] = { callback = callback, result = result }
        end)
      end
      return original_system(args, opts, callback)
    end

    vim.cmd.edit(vim.fn.fnameescape(repo .. "/A"))
    local buf = vim.api.nvim_get_current_buf()
    assert(
      vim.wait(3000, function()
        return #held > 0 and held[1].result.stdout == "old\n"
      end, 20),
      "real old-index Git show did not finish"
    )
    local old = table.remove(held, 1)

    git.run(repo, "add", "A")
    assert(git.run(repo, "show", ":A") == "new\n", "new index oracle differs")
    assert(git.read(repo .. "/A") == "new\n", "buffer disk oracle differs")
    vim.cmd.edit(vim.fn.fnameescape(repo .. "/A"))
    assert(
      vim.api.nvim_get_current_buf() == buf,
      "edit unexpectedly replaced buffer"
    )
    assert(
      vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "new" })
        and vim.bo[buf].endofline,
      "buffer no longer matches the new indexed bytes"
    )
    assert(
      vim.wait(3000, function()
        for _, reply in ipairs(held) do
          if reply.result.stdout == "new\n" then
            return true
          end
        end
        return false
      end, 20),
      "real new-index Git show did not finish"
    )

    local accepted_new = false
    for _, reply in ipairs(held) do
      if reply.result.stdout == "new\n" then
        assert(reply.result.code == 0, "new index query failed")
        reply.callback(reply.result)
        accepted_new = true
      end
    end
    assert(accepted_new, "no new snapshot was accepted")
    flush()
    assert(#git.signs(buf) == 0, "new index matching buffer still has signs")
    assert(
      old.result.code == 0 and old.result.stdout == "old\n",
      "old Git result is not real S0"
    )
    old.callback(old.result)
    flush()
    assert(
      #git.signs(buf) == 0,
      "superseded index result restored signs: " .. vim.inspect(git.signs(buf))
    )
  end, debug.traceback)

  vim.system = original_system
  vim.cmd.enew({ bang = true })
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

T["stale Git failure preserves the latest sign and current failure clears it"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp((vim.env.TMPDIR or "/tmp") .. "/poincare-race-XXXXXX")
  )
  local repo = dir .. "/repo"
  local original_system = vim.system
  local held = {}

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
      "initial real index did not produce a change sign"
    )

    vim.system = function(args, opts, callback)
      if args[1] == "git" and args[2] == "show" and callback then
        return original_system(args, opts, function(result)
          held[#held + 1] = { callback = callback, result = result }
        end)
      end
      return original_system(args, opts, callback)
    end
    local function request(count)
      vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
      assert(
        vim.wait(3000, function()
          return #held == count
        end, 20),
        "real Git show callback did not arrive"
      )
      return held[count]
    end

    git.run(repo, "rm", "-f", "-q", "--cached", "A")
    local stale_failure = request(1)
    assert(stale_failure.result.code ~= 0, "old missing-index result succeeded")

    git.write(repo .. "/A", "indexed\n")
    git.run(repo, "add", "A")
    git.write(repo .. "/A", "working\n")
    assert(git.run(repo, "show", ":A") == "indexed\n")
    local latest_success = request(2)
    assert(latest_success.result.code == 0, "latest real Git show failed")
    latest_success.callback(latest_success.result)
    flush()
    assert(vim.deep_equal(git.signs(buf), { "GitGutterChange" }))

    stale_failure.callback(stale_failure.result)
    flush()
    assert(
      vim.deep_equal(git.signs(buf), { "GitGutterChange" }),
      "stale failure cleared latest sign"
    )

    git.run(repo, "rm", "-f", "-q", "--cached", "A")
    local current_failure = request(3)
    assert(
      current_failure.result.code ~= 0,
      "current missing-index result succeeded"
    )
    current_failure.callback(current_failure.result)
    flush()
    assert(#git.signs(buf) == 0, "current failure did not clear its own signs")
  end, debug.traceback)

  vim.system = original_system
  vim.cmd.enew({ bang = true })
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

T["held replies cannot cross a buffer path or repository root"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp((vim.env.TMPDIR or "/tmp") .. "/poincare-race-XXXXXX")
  )
  local first, second, outside =
    dir .. "/first", dir .. "/second", dir .. "/out"
  local original_system = vim.system
  local held = {}

  local ok, err = xpcall(function()
    for _, repo in ipairs({ first, second }) do
      vim.fn.mkdir(repo, "p")
      git.run(repo, "init", "-q")
    end
    vim.fn.mkdir(outside, "p")
    git.write(first .. "/A", "old\n")
    git.run(first, "add", "A")
    git.write(first .. "/A", "working\n")
    git.write(second .. "/B", "other\n")
    git.run(second, "add", "B")
    assert(git.run(second, "show", ":B") == "other\n")

    vim.cmd.edit(vim.fn.fnameescape(first .. "/A"))
    local buf = vim.api.nvim_get_current_buf()
    assert(
      vim.wait(3000, function()
        return vim.deep_equal(git.signs(buf), { "GitGutterChange" })
      end, 20),
      "first root did not get a settled sign"
    )

    vim.system = function(args, opts, callback)
      if args[1] == "git" and args[2] == "show" and callback then
        return original_system(args, opts, function(result)
          held[#held + 1] = {
            callback = callback,
            result = result,
            root = opts.cwd,
          }
        end)
      end
      return original_system(args, opts, callback)
    end
    local function request(count)
      vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
      assert(
        vim.wait(3000, function()
          return #held == count
        end, 20),
        "real held Git show did not finish"
      )
      return held[count]
    end
    local old_success = request(1)
    assert(old_success.result.code == 0 and old_success.root == first)
    git.run(first, "rm", "-f", "-q", "--cached", "A")
    local old_failure = request(2)
    assert(old_failure.result.code ~= 0 and old_failure.root == first)

    vim.cmd.file(vim.fn.fnameescape(second .. "/B"))
    assert(vim.api.nvim_get_current_buf() == buf)
    assert(vim.fs.root(buf, ".git") == second, "root did not transition")
    assert(#git.signs(buf) == 0, "rename did not clear the first root's signs")
    assert(
      vim.wait(3000, function()
        return #held >= 3 and held[#held].root == second
      end, 20),
      "new root did not produce a real Git result"
    )
    local new_success = held[#held]
    assert(
      new_success.result.code == 0 and new_success.result.stdout == "other\n"
    )
    new_success.callback(new_success.result)
    flush()
    assert(
      vim.deep_equal(git.signs(buf), { "GitGutterChange" }),
      "new root did not own its sign"
    )
    for _, stale in ipairs({ old_success, old_failure }) do
      stale.callback(stale.result)
      flush()
      assert(
        vim.deep_equal(git.signs(buf), { "GitGutterChange" }),
        "old root reply changed new root signs"
      )
    end

    local pending_new = request(#held + 1)
    assert(pending_new.root == second and pending_new.result.code == 0)
    vim.cmd.file(vim.fn.fnameescape(outside .. "/C"))
    assert(vim.fs.root(buf, ".git") == nil)
    assert(#git.signs(buf) == 0, "ineligible rename retained signs")
    pending_new.callback(pending_new.result)
    flush()
    assert(#git.signs(buf) == 0, "detached response restored signs")
  end, debug.traceback)

  vim.system = original_system
  vim.cmd.enew({ bang = true })
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

T["missing real Git clears settled signs and a later refresh restores them"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp((vim.env.TMPDIR or "/tmp") .. "/poincare-spawn-XXXXXX")
  )
  local repo = dir .. "/repo"
  local original_path = vim.env.PATH

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
      "real Git did not settle the initial sign"
    )

    local git_bin = vim.fs.dirname(vim.fn.exepath("git"))
    local remaining = {}
    for _, entry in ipairs(vim.split(original_path, ":", { plain = true })) do
      if entry ~= git_bin then
        remaining[#remaining + 1] = entry
      end
    end
    vim.env.PATH = table.concat(remaining, ":")
    assert(vim.fn.executable("git") == 0, "real Git is still on PATH")
    vim.v.errmsg = ""
    local triggered, trigger_err =
      pcall(vim.api.nvim_exec_autocmds, "BufEnter", { buffer = buf })
    assert(
      triggered,
      "missing Git raised an autocmd error: " .. tostring(trigger_err)
    )
    assert(vim.v.errmsg == "", "missing Git reported: " .. vim.v.errmsg)
    assert(#git.signs(buf) == 0, "missing Git left stale change signs")

    vim.env.PATH = original_path
    assert(vim.fn.executable("git") == 1, "real Git was not restored")
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
    assert(
      vim.wait(3000, function()
        return vim.deep_equal(git.signs(buf), { "GitGutterChange" })
      end, 20),
      "normal refresh did not restore the real Git sign"
    )
    assert(git.run(repo, "show", ":A") == "indexed\n")
    assert(git.read(repo .. "/A") == "working\n")
  end, debug.traceback)

  vim.env.PATH = original_path
  vim.cmd.enew({ bang = true })
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

T["held real Git result cannot restore signs for nofile"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp((vim.env.TMPDIR or "/tmp") .. "/poincare-buftype-XXXXXX")
  )
  local repo = dir .. "/repo"
  local original_system = vim.system
  local held = {}

  local ok, err = xpcall(function()
    vim.fn.mkdir(repo, "p")
    git.run(repo, "init", "-q")
    git.write(repo .. "/A", "indexed\n")
    git.run(repo, "add", "A")
    git.write(repo .. "/A", "working\n")
    assert(git.run(repo, "show", ":A") == "indexed\n")

    vim.system = function(args, opts, callback)
      if args[1] == "git" and args[2] == "show" and callback then
        local reply = { callback = callback }
        held[#held + 1] = reply
        return original_system(args, opts, function(result)
          reply.result = result
        end)
      end
      return original_system(args, opts, callback)
    end

    vim.cmd.edit(vim.fn.fnameescape(repo .. "/A"))
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
    local pending = held[#held]
    assert(pending, "real Git show was not launched")
    assert(
      vim.wait(3000, function()
        return pending.result ~= nil
      end, 20),
      "real held Git result did not finish"
    )
    assert(
      pending.result.code == 0 and pending.result.stdout == "indexed\n",
      "held result did not contain real indexed bytes"
    )

    vim.cmd("setlocal buftype=nofile")
    assert(vim.bo[buf].buftype == "nofile")
    assert(#git.signs(buf) == 0, "ineligible transition retained signs")
    pending.callback(pending.result)
    flush()
    assert(#git.signs(buf) == 0, "held Git result signed an ineligible buffer")

    local previous = #held
    vim.cmd("setlocal buftype=")
    assert(vim.bo[buf].buftype == "")
    assert(#held > previous, "returning to an eligible type did not query Git")
    local renewed = held[#held]
    assert(
      vim.wait(3000, function()
        return renewed.result ~= nil
      end, 20),
      "real refreshed Git result did not finish"
    )
    assert(renewed.result.code == 0 and renewed.result.stdout == "indexed\n")
    renewed.callback(renewed.result)
    flush()
    assert(
      vim.deep_equal(git.signs(buf), { "GitGutterChange" }),
      "returning to an eligible type did not restore the real Git sign"
    )
  end, debug.traceback)

  vim.system = original_system
  vim.cmd.enew({ bang = true })
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

return T
