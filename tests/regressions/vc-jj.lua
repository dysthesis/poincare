local T = require("mini.test").new_set()
local git = dofile("tests/regressions/git.lua")

T["a missing real jj settles until ordinary refresh after restoration"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp((vim.env.TMPDIR or "/tmp") .. "/poincare-vc-jj-XXXXXX")
  )
  local repo = dir .. "/repo"
  local original_path = vim.env.PATH
  local original_system = vim.system
  local original_statusline = vim.o.statusline
  local calls, successes, fallback, missing = 0, 0, 0, nil

  local ok, err = xpcall(function()
    assert(vim.env.TEST_JJ_BIN and vim.env.TEST_JJ_BIN ~= "")
    assert(vim.fn.executable("jj") == 0, "jj was not initially unavailable")
    vim.fn.mkdir(vim.env.XDG_CONFIG_HOME .. "/jj", "p")
    git.write(
      vim.env.XDG_CONFIG_HOME .. "/jj/config.toml",
      '[user]\nname = "Regression"\nemail = "test@example.invalid"\n'
    )
    local init = assert(original_system({
      vim.env.TEST_JJ_BIN .. "/jj",
      "git",
      "init",
      "--no-colocate",
      repo,
    }, { text = true }):wait(5000))
    assert(init.code == 0, "real jj init failed: " .. (init.stderr or ""))
    assert(vim.fn.isdirectory(repo .. "/.jj") == 1, "not a jj workspace")
    assert(
      vim.fn.isdirectory(repo .. "/.git") == 0,
      "unexpected Git fallback root"
    )
    git.write(repo .. "/A", "content\n")
    local oracle = assert(original_system({
      vim.env.TEST_JJ_BIN .. "/jj",
      "--repository",
      repo,
      "--no-pager",
      "log",
      "--no-graph",
      "-r",
      "@",
      "-T",
      'change_id.shortest(8) ++ "\\n"',
    }, { text = true }):wait(5000))
    assert(oracle.code == 0, "real jj log failed: " .. (oracle.stderr or ""))
    local label = vim.trim(oracle.stdout or "")
    assert(label ~= "", "real jj log returned no change id")

    vim.system = function(args, opts, callback)
      if args[1] == "git" and args[4] == "status" then
        fallback = fallback + 1
      end
      if args[1] ~= "jj" or not callback then
        return original_system(args, opts, callback)
      end
      calls = calls + 1
      if calls >= 3 then
        vim.o.statusline = "" -- Bound a regression that retries on redraw.
      end
      local started, result = pcall(original_system, args, opts, function(reply)
        if reply.code == 0 then
          successes = successes + 1
        end
        callback(reply)
      end)
      if not started then
        missing = result
        error(result)
      end
      return result
    end

    local opened, open_err =
      pcall(vim.cmd.edit, vim.fn.fnameescape(repo .. "/A"))
    if not opened then
      assert(tostring(open_err):find("ENOENT", 1, true), tostring(open_err))
    end
    assert(
      missing and tostring(missing):find("ENOENT", 1, true),
      "jj spawn did not fail synchronously"
    )
    local buf = vim.api.nvim_get_current_buf()
    assert(
      vim.api.nvim_buf_get_name(buf) == repo .. "/A",
      "missing-jj file was not opened"
    )
    for _ = 1, 3 do
      pcall(vim.cmd.redrawstatus)
      pcall(vim.api.nvim_eval_statusline, vim.o.statusline, {
        winid = vim.api.nvim_get_current_win(),
      })
    end
    assert(calls == 1 and fallback == 0, "missing backend retried or fell back")

    vim.env.PATH = original_path .. ":" .. vim.env.TEST_JJ_BIN
    assert(vim.fn.executable("jj") == 1, "real jj was not restored")
    local vc = require("ui.statusline.vc")
    vc.refresh(buf) -- Normal module refresh, not a fabricated backend callback.
    local rendered
    assert(
      vim.wait(3000, function()
        rendered = vim.api.nvim_eval_statusline(vim.o.statusline, {
          winid = vim.api.nvim_get_current_win(),
        }).str
        return successes == 1 and rendered:find(label, 1, true) ~= nil
      end, 20),
      "real jj did not recover on normal refresh: " .. tostring(rendered)
    )
    assert(
      calls == 2 and fallback == 0,
      "recovery retried or used Git fallback"
    )
  end, debug.traceback)

  vim.o.statusline = ""
  vim.system = original_system
  vim.cmd.enew({ bang = true })
  vim.env.PATH = original_path
  vim.o.statusline = original_statusline
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

return T
