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

return T
