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

return T
