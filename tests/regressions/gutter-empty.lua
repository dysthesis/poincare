local T = require("mini.test").new_set()
local git = dofile("tests/regressions/git.lua")

T["unchanged zero-byte index and disk do not produce gutter additions"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp((vim.env.TMPDIR or "/tmp") .. "/poincare-empty-XXXXXX")
  )
  local repo = dir .. "/repo"
  local original_system = vim.system
  local started, completed = 0, 0

  local ok, err = xpcall(function()
    vim.fn.mkdir(repo, "p")
    git.run(repo, "init", "-q")
    local fixtures = { empty = "", newline = "\n", nonempty = "unchanged\n" }
    for name, bytes in pairs(fixtures) do
      git.write(repo .. "/" .. name, bytes)
      git.run(repo, "add", name)
      assert(git.read(repo .. "/" .. name) == bytes, "disk oracle for " .. name)
      assert(
        git.run(repo, "show", ":" .. name) == bytes,
        "index oracle for " .. name
      )
    end

    vim.system = function(args, opts, callback)
      if args[1] == "git" and args[2] == "show" and callback then
        started = started + 1
        return original_system(args, opts, function(result)
          completed = completed + 1
          callback(result)
        end)
      end
      return original_system(args, opts, callback)
    end

    local function sample(name, bytes)
      local prior = started
      vim.cmd.edit(vim.fn.fnameescape(repo .. "/" .. name))
      local buf = vim.api.nvim_get_current_buf()
      assert(
        vim.wait(3000, function()
          return started > prior and completed == started
        end, 20),
        "indexed Git show did not settle for " .. name
      )
      local done = false
      vim.schedule(function()
        done = true
      end)
      assert(
        vim.wait(1000, function()
          return done
        end, 10),
        "gutter render did not settle"
      )
      if name == "empty" or name == "newline" then
        assert(
          vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "" })
            and vim.bo[buf].endofline,
          "empty and one-newline buffers must retain their shared visible shape"
        )
      end
      local before = git.signs(buf)
      assert(
        git.read(repo .. "/" .. name) == bytes,
        "read mutated disk " .. name
      )
      assert(
        git.run(repo, "show", ":" .. name) == bytes,
        "read mutated index " .. name
      )

      vim.cmd.write()
      assert(
        git.read(repo .. "/" .. name) == bytes,
        "unchanged write altered bytes " .. name
      )
      assert(
        git.run(repo, "show", ":" .. name) == bytes,
        "write altered index " .. name
      )
      return before, git.signs(buf)
    end

    local empty_before, empty_after = sample("empty", "")
    local newline_before, newline_after = sample("newline", "\n")
    local nonempty_before, nonempty_after = sample("nonempty", "unchanged\n")
    assert(
      #newline_before == 0 and #newline_after == 0,
      "newline control gained signs"
    )
    assert(
      #nonempty_before == 0 and #nonempty_after == 0,
      "nonempty control gained signs"
    )
    assert(
      #empty_before == 0 and #empty_after == 0,
      ("zero-byte file got signs before=%s after=%s"):format(
        vim.inspect(empty_before),
        vim.inspect(empty_after)
      )
    )
  end, debug.traceback)

  vim.system = original_system
  vim.cmd.enew({ bang = true })
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

T["deleting the final indexed line keeps a zero-byte gutter diff across write"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp((vim.env.TMPDIR or "/tmp") .. "/poincare-empty-XXXXXX")
  )
  local repo = dir .. "/repo"
  local original_system = vim.system
  local started, completed = 0, 0

  local ok, err = xpcall(function()
    vim.fn.mkdir(repo, "p")
    git.run(repo, "init", "-q")
    git.write(repo .. "/A", "old\n")
    git.run(repo, "add", "A")

    vim.system = function(args, opts, callback)
      if args[1] == "git" and args[2] == "show" and callback then
        started = started + 1
        return original_system(args, opts, function(result)
          completed = completed + 1
          callback(result)
        end)
      end
      return original_system(args, opts, callback)
    end

    vim.cmd.edit(vim.fn.fnameescape(repo .. "/A"))
    local buf = vim.api.nvim_get_current_buf()
    assert(
      vim.wait(3000, function()
        return started > 0 and completed == started
      end, 20),
      "indexed Git snapshot did not settle"
    )
    local rendered = false
    vim.schedule(function()
      rendered = true
    end)
    assert(vim.wait(1000, function()
      return rendered
    end, 10))
    assert(#git.signs(buf) == 0, "clean indexed line had a sign")

    vim.cmd("normal! dd")
    assert(vim.fn.wordcount().bytes == 0, "delete did not empty the buffer")
    -- :normal! runs inside this test's Lua callback; emit its deferred event.
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
    assert(
      vim.deep_equal(git.signs(buf), { "GitGutterDelete" }),
      "deleting the final line did not get a deletion sign"
    )
    vim.cmd.write()
    assert(git.read(repo .. "/A") == "", "delete did not write zero bytes")
    assert(git.run(repo, "show", ":A") == "old\n", "index was changed")
    assert(
      vim.deep_equal(git.signs(buf), { "GitGutterDelete" }),
      "write lost the zero-byte gutter diff"
    )
  end, debug.traceback)

  vim.system = original_system
  vim.cmd.enew({ bang = true })
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

T["newline metadata and pre-write edits update signs from the cached index"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp((vim.env.TMPDIR or "/tmp") .. "/poincare-eol-XXXXXX")
  )
  local repo = dir .. "/repo"
  local original_system = vim.system
  local started, completed = 0, 0
  local write_group

  local ok, err = xpcall(function()
    vim.fn.mkdir(repo, "p")
    git.run(repo, "init", "-q")

    vim.system = function(args, opts, callback)
      if args[1] == "git" and args[2] == "show" and callback then
        started = started + 1
        return original_system(args, opts, function(result)
          completed = completed + 1
          callback(result)
        end)
      end
      return original_system(args, opts, callback)
    end

    local function open_indexed(name, bytes)
      local path = repo .. "/" .. name
      git.write(path, bytes)
      git.run(repo, "add", name)
      local previous = started
      vim.cmd.edit(vim.fn.fnameescape(path))
      local buf = vim.api.nvim_get_current_buf()
      assert(
        vim.wait(3000, function()
          return started > previous and completed == started
        end, 20),
        "index lookup did not complete for " .. name
      )
      local rendered = false
      vim.schedule(function()
        rendered = true
      end)
      assert(vim.wait(1000, function()
        return rendered
      end, 10))
      assert(#git.signs(buf) == 0, "indexed file was not initially clean")
      return path, buf
    end

    for _, fixture in ipairs({
      { "newline", "\n", "", "GitGutterDelete" },
      { "nonempty", "A\n", "A", "GitGutterChange" },
    }) do
      local name, indexed, saved, sign = unpack(fixture)
      local path, buf = open_indexed(name, indexed)
      vim.bo[buf].fixendofline = false
      vim.bo[buf].endofline = false
      vim.cmd.write()
      assert(git.read(path) == saved, "wrong saved bytes for " .. name)
      assert(git.run(repo, "show", ":" .. name) == indexed, "index changed")
      assert(
        vim.deep_equal(git.signs(buf), { sign }),
        "newline-only edit had wrong signs for " .. name
      )
      if name == "nonempty" then
        vim.cmd("setlocal endofline")
        assert(#git.signs(buf) == 0, "OptionSet endofline kept old signs")
        vim.cmd("setlocal noendofline")
        assert(
          vim.deep_equal(git.signs(buf), { sign }),
          "OptionSet noendofline did not restore the sign"
        )
      end
    end

    local path, buf = open_indexed("prewrite", "A\n")
    vim.bo[buf].fixendofline = false
    write_group = vim.api.nvim_create_augroup("gutter_prewrite_regression", {
      clear = true,
    })
    vim.api.nvim_create_autocmd("BufWritePre", {
      group = write_group,
      buffer = buf,
      once = true,
      callback = function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "formatted" })
        vim.bo[buf].endofline = false
      end,
    })
    vim.cmd.write()
    assert(git.read(path) == "formatted", "pre-write bytes were not written")
    assert(git.run(repo, "show", ":prewrite") == "A\n", "index changed")
    assert(
      vim.deep_equal(git.signs(buf), { "GitGutterChange" }),
      "pre-write buffer change did not update the gutter"
    )
  end, debug.traceback)

  if write_group then
    vim.api.nvim_del_augroup_by_id(write_group)
  end
  vim.system = original_system
  vim.cmd.enew({ bang = true })
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

return T
