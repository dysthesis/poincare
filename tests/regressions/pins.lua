local T = require("mini.test").new_set()

T["pins stay inside the current project across reload and selection"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp((vim.env.TMPDIR or "/tmp") .. "/poincare-pins-XXXXXX")
  )
  local root = dir .. "/project"
  local nested = root .. "/nested/in.txt"
  local outside = dir .. "/outside.txt"
  local sibling = dir .. "/project-sibling/out.txt"
  local previous = vim.fn.getcwd()
  local original_module = package.loaded.pins
  local file = vim.fs.joinpath(
    vim.fn.stdpath("state"),
    "pins",
    vim.fn.sha256(root) .. ".json"
  )

  local ok, err = xpcall(function()
    vim.fn.mkdir(root .. "/nested", "p")
    vim.fn.mkdir(dir .. "/project-sibling", "p")
    for _, path in ipairs({ nested, outside, sibling }) do
      assert(vim.fn.writefile({ "content" }, path) == 0)
    end
    vim.fn.chdir(root)
    local function saved()
      assert(vim.fn.filereadable(file) == 1, "pin state was not persisted")
      local value = vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
      assert(type(value) == "table", "pin state is not a JSON list")
      for _, path in ipairs(value) do
        assert(
          type(path) == "string"
            and path == vim.fs.normalize(path)
            and vim.startswith(path, root .. "/"),
          "persistent pin escaped the normalized project: " .. vim.inspect(path)
        )
      end
      return value
    end

    local pins = require("pins")
    vim.cmd.edit(vim.fn.fnameescape(nested))
    pins.toggle()
    assert(vim.deep_equal(saved(), { nested }), "nested file was not saved")

    for _, path in ipairs({ outside, sibling }) do
      vim.cmd.edit(vim.fn.fnameescape(path))
      assert(vim.fs.root(path, ".git") == nil, "outside file has a Git root")
      pins.toggle()
      assert(vim.deep_equal(saved(), { nested }), "outside toggle changed pins")
    end

    -- A previously persisted external path must not become usable on reload.
    assert(
      vim.fn.writefile({ vim.json.encode({ nested, outside, sibling }) }, file)
        == 0
    )
    package.loaded.pins = nil
    local reloaded = require("pins")
    vim.cmd.edit(vim.fn.fnameescape(nested))
    reloaded.select(2)
    assert(
      vim.api.nvim_buf_get_name(0) == nested,
      "legacy external pin was selected"
    )
    assert(
      vim.deep_equal(saved(), { nested }),
      "legacy paths survived migration"
    )
    vim.cmd.edit(vim.fn.fnameescape(outside))
    reloaded.select(1)
    assert(
      vim.api.nvim_buf_get_name(0) == nested,
      "local pin could not be selected"
    )
  end, debug.traceback)

  package.loaded.pins = original_module
  vim.cmd.enew({ bang = true })
  vim.fn.chdir(previous)
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

return T
