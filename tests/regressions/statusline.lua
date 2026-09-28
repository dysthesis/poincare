local T = require("mini.test").new_set()

T["filename is inert when the active statusline is evaluated"] = function()
  local dir = assert(
    vim.uv.fs_mkdtemp(
      (vim.env.TMPDIR or "/tmp") .. "/poincare-statusline-XXXXXX"
    )
  )
  local previous = vim.fn.getcwd()
  local name = '%{writefile(["safe-marker"],"actual-marker")}'

  local ok, err = xpcall(function()
    vim.fn.chdir(dir)
    assert(vim.fn.writefile({ "plain" }, dir .. "/plain.txt") == 0)
    assert(vim.fn.writefile({ "payload" }, dir .. "/" .. name) == 0)

    local function display(filename)
      vim.cmd.edit(vim.fn.fnameescape(dir .. "/" .. filename))
      vim.cmd.redrawstatus()
      return vim.api.nvim_eval_statusline(vim.o.statusline, {
        winid = vim.api.nvim_get_current_win(),
      }).str
    end

    assert(
      display("plain.txt"):find("plain.txt", 1, true),
      "control filename was not displayed"
    )
    assert(
      vim.fn.filereadable(dir .. "/actual-marker") == 0,
      "control created the marker"
    )
    local rendered = display(name)
    assert(
      vim.fn.filereadable(dir .. "/actual-marker") == 0,
      "display executed the filename"
    )
    assert(
      rendered:find(name, 1, true),
      "the filename was not displayed literally: " .. rendered
    )
  end, debug.traceback)

  vim.cmd.enew({ bang = true })
  vim.fn.chdir(previous)
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

T["project, real Git branch and LSP names remain literal during evaluation"] = function()
  local git = dofile("tests/regressions/git.lua")
  local dir = assert(
    vim.uv.fs_mkdtemp(
      (vim.env.TMPDIR or "/tmp") .. "/poincare-statusline-XXXXXX"
    )
  )
  local previous = vim.fn.getcwd()
  local original_clients = vim.lsp.get_clients
  local project = '%{writefile(["safe-marker"],"project-marker")}'
  local branch = '%{system("echo>branch-marker")}'
  local client = '%{writefile(["safe-marker"],"client-marker")}'

  local ok, err = xpcall(function()
    local function evaluate()
      vim.cmd.redrawstatus()
      return vim.api.nvim_eval_statusline(vim.o.statusline, {
        winid = vim.api.nvim_get_current_win(),
        highlights = true,
        maxwidth = 320,
      })
    end

    local function open(root, clients)
      vim.lsp.get_clients = function()
        return { { name = clients } }
      end
      vim.fn.chdir(root)
      vim.cmd.edit(vim.fn.fnameescape(root .. "/plain.txt"))
    end

    local plain = dir .. "/plain-project"
    local crafted = dir .. "/" .. project
    for _, entry in ipairs({
      { plain, "plain-branch" },
      { crafted, branch },
    }) do
      vim.fn.mkdir(entry[1], "p")
      git.run(entry[1], "init", "-q", "-b", entry[2])
      git.write(entry[1] .. "/plain.txt", "content\n")
      assert(
        git
          .run(entry[1], "status", "--porcelain=v2", "--branch")
          :find("# branch.head " .. entry[2], 1, true),
        "real Git branch oracle differs"
      )
    end

    open(plain, "plain-client")
    local control
    assert(
      vim.wait(3000, function()
        control = evaluate()
        return control.str:find("plain-branch", 1, true) ~= nil
      end, 20),
      "plain real-Git branch was not displayed"
    )
    for _, value in ipairs({ "plain.txt", "plain-project", "plain-client" }) do
      assert(
        control.str:find(value, 1, true),
        "plain control missing " .. value
      )
    end

    open(crafted, client)
    local rendered
    assert(
      vim.wait(3000, function()
        rendered = evaluate()
        return rendered.str:find(branch, 1, true) ~= nil
      end, 20),
      "real Git branch was not displayed literally"
    )
    for _, value in ipairs({ project, client, "plain.txt" }) do
      assert(
        rendered.str:find(value, 1, true),
        "literal data missing: " .. value
      )
    end
    for _, marker in ipairs({
      "project-marker",
      "branch-marker",
      "client-marker",
    }) do
      assert(
        vim.fn.filereadable(crafted .. "/" .. marker) == 0,
        "executed " .. marker
      )
    end
    local groups = {}
    for _, highlight in ipairs(rendered.highlights) do
      groups[highlight.group] = true
    end
    for _, group in ipairs({
      "StatusLineName",
      "StatusLineVc",
      "StatusLineLsp",
      "StatusLineProject",
    }) do
      assert(groups[group], "authored highlight missing: " .. group)
    end
    assert(rendered.str:find("  ", 1, true), "authored alignment disappeared")
  end, debug.traceback)

  vim.lsp.get_clients = original_clients
  vim.cmd.enew({ bang = true })
  vim.fn.chdir(previous)
  vim.fn.delete(dir, "rf")
  assert(ok, err)
end

return T
