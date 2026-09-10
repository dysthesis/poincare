local MiniTest = require("mini.test")

local test_file = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local root = vim.fs.dirname(vim.fs.dirname(test_file))

local register = dofile(root .. "/src/lua/lang/modules/linters.lua")
local original_notify = vim.notify
vim.notify = function() end

local dir = assert(vim.uv.fs_mkdtemp("/tmp/poincare-linters-XXXXXX"))
local T = MiniTest.new_set({
  hooks = {
    post_once = function()
      vim.notify = original_notify
      vim.fn.delete(dir, "rf")
    end,
  },
})

local function fake(name, definition)
  package.preload["lang.linters." .. name] = function()
    return definition
  end
  -- require() caches a successful load; make sure this one is used.
  package.loaded["lang.linters." .. name] = nil

  return definition
end

local function case(filetype, lines, spec)
  local bufnr = vim.api.nvim_create_buf(true, false)

  vim.bo[bufnr].filetype = filetype

  if lines then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end

  register({ filetypes = { filetype } }, spec)

  return bufnr
end

local function write(bufnr, name)
  vim.v.errmsg = ""
  vim.api.nvim_buf_set_name(bufnr, name)
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("silent write!")
  end)
  assert(vim.v.errmsg == "", "write raised a callback error: " .. vim.v.errmsg)
end

local function wait_for(predicate, what)
  assert(vim.wait(2000, predicate, 10), what)
end

-- Spin the event loop so negative assertions still see any late callback.
local function spin(ms)
  vim.wait(ms, function()
    return false
  end, 10)
end

local function diagnostics(bufnr, name)
  local namespace = vim.api.nvim_get_namespaces()["lang/linter/" .. name]

  return namespace and vim.diagnostic.get(bufnr, { namespace = namespace })
    or {}
end

local fields = {
  "lnum",
  "col",
  "end_lnum",
  "end_col",
  "severity",
  "message",
  "source",
  "code",
}

local function assert_diagnostic(got, expected, what)
  assert(got ~= nil, what .. " is missing")

  for _, field in ipairs(fields) do
    assert(
      got[field] == expected[field],
      ("%s %s: got %s"):format(what, field, vim.inspect(got[field]))
    )
  end
end

T["a registered linter publishes its diagnostics"] = function()
  local bufnr
  local ran = false

  fake("sh", {
    cmd = function(ctx)
      assert(ctx.bufnr == bufnr, "ctx.bufnr is not the linted buffer")
      assert(ctx.filename == dir .. "/happy.lua", "ctx.filename is wrong")
      assert(ctx.cwd == dir, "ctx.cwd is wrong")
      return { "sh", "-c", "printf sh-ran", ctx.filename }
    end,
    parse = function()
      ran = true
      return {
        {
          lnum = 1,
          col = 2,
          end_lnum = 3,
          end_col = 4,
          severity = vim.diagnostic.severity.ERROR,
          message = "broken",
          source = "sh",
          code = "E042",
        },
      }
    end,
  })
  bufnr = case("happy", { "hello" }, "sh")

  write(bufnr, dir .. "/happy.lua")
  wait_for(function()
    return ran
  end, "the linter never ran")

  local got = diagnostics(bufnr, "sh")

  assert(#got == 1, "the linter published " .. #got .. " diagnostics")
  assert_diagnostic(got[1], {
    lnum = 1,
    col = 2,
    end_lnum = 3,
    end_col = 4,
    severity = vim.diagnostic.severity.ERROR,
    message = "broken",
    source = "sh",
    code = "E042",
  }, "published diagnostic")
end

T["a re-run replaces the previous diagnostics"] = function()
  local runs = 0

  fake("cat", {
    cmd = function(ctx)
      return { "cat", ctx.filename }
    end,
    parse = function()
      runs = runs + 1
      return {
        {
          lnum = runs - 1,
          col = 0,
          severity = vim.diagnostic.severity.WARN,
          message = "run " .. runs,
          source = "cat",
        },
      }
    end,
  })
  local bufnr = case("rerun", { "line" }, "cat")

  write(bufnr, dir .. "/rerun.txt")
  wait_for(function()
    return runs >= 1
  end, "the first lint never ran")
  assert(#diagnostics(bufnr, "cat") == 1, "the first run published diagnostics")

  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr })
  wait_for(function()
    return runs >= 2
  end, "the second lint never ran")

  local got = diagnostics(bufnr, "cat")

  assert(#got == 1, "a re-run appended instead of replacing")
  assert_diagnostic(got[1], {
    lnum = 1,
    col = 0,
    severity = vim.diagnostic.severity.WARN,
    message = "run 2",
    source = "cat",
  }, "the second run's diagnostic")
end

T["a superseded run's output is discarded"] = function()
  local calls = 0
  local parsed = {}

  fake("sleep", {
    cmd = function(ctx)
      calls = calls + 1

      if calls == 1 then
        return { "sh", "-c", "sleep 0.3; printf slow", ctx.filename }
      end

      return { "sh", "-c", "printf fast", ctx.filename }
    end,
    parse = function(result)
      parsed[#parsed + 1] = result.stdout
      return {
        {
          lnum = 0,
          col = 0,
          severity = vim.diagnostic.severity.ERROR,
          message = result.stdout,
          source = "sleep",
        },
      }
    end,
  })
  local bufnr = case("supersede", { "line" }, "sleep")

  write(bufnr, dir .. "/supersede.txt")
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr })
  wait_for(function()
    return #parsed > 0
  end, "no lint finished")

  -- The killed run would land within its sleep were its output kept.
  spin(400)
  assert(#parsed == 1, "a superseded run reached parse")
  assert(parsed[1] == "fast", "the surviving output is not the newest run's")

  local got = diagnostics(bufnr, "sleep")

  assert(#got == 1, "expected one diagnostic")
  assert_diagnostic(got[1], {
    lnum = 0,
    col = 0,
    severity = vim.diagnostic.severity.ERROR,
    message = "fast",
    source = "sleep",
  }, "published diagnostic")
end

T["an unnamed buffer is not linted"] = function()
  local ran = false

  fake("true", {
    cmd = function()
      return { "true" }
    end,
    parse = function()
      ran = true
      return {}
    end,
  })
  local bufnr = case("unnamed", { "line" }, "true")

  vim.v.errmsg = ""
  local ok, err =
    pcall(vim.api.nvim_exec_autocmds, "BufWritePost", { buffer = bufnr })

  assert(ok, err)
  spin(100)
  assert(not ran, "an unnamed buffer was linted")
  assert(
    vim.v.errmsg == "",
    "linting an unnamed buffer raised: " .. vim.v.errmsg
  )
end

T["a buffer wiped mid-lint is tolerated"] = function()
  local ran = false
  local signal = dir .. "/wiped-signal"

  fake("false", {
    cmd = function(ctx)
      return { "sh", "-c", "sleep 0.2; printf done > " .. signal, ctx.filename }
    end,
    parse = function()
      ran = true
      return {}
    end,
  })
  local bufnr = case("wiped", { "line" }, "false")

  write(bufnr, dir .. "/wiped.txt")
  vim.api.nvim_buf_delete(bufnr, { force = true })

  vim.v.errmsg = ""
  local ok, finished = pcall(vim.wait, 2000, function()
    return vim.uv.fs_stat(signal) ~= nil
  end, 10)

  assert(ok and finished, "the in-flight lint never finished")
  spin(50)
  assert(not ran, "a wiped buffer's lint result was published")
  assert(vim.v.errmsg == "", "a wiped buffer's lint raised: " .. vim.v.errmsg)
end

T["a missing executable is skipped with a warning"] = function()
  local runs = 0

  fake("tr", {
    cmd = function()
      return { "true" }
    end,
    parse = function()
      runs = runs + 1
      return {}
    end,
  })
  local notifications = {}
  local notify = vim.notify

  vim.notify = function(message, level)
    notifications[#notifications + 1] = { message, level }
  end
  local bufnr = case("missing", { "line" }, { "poincare-no-such-linter", "tr" })
  vim.notify = notify

  assert(#notifications == 1, "expected exactly one skip notification")
  assert(
    notifications[1][1]:find("poincare-no-such-linter", 1, true) ~= nil,
    "the skip notification does not name the missing linter"
  )
  assert(
    notifications[1][2] == vim.log.levels.WARN,
    "the skip notification is not a warning"
  )

  write(bufnr, dir .. "/missing.txt")
  wait_for(function()
    return runs >= 1
  end, "the available linter never ran")

  register({ filetypes = { "missing" } }, { "poincare-no-such-linter" })
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr })
  spin(100)
  assert(runs == 1, "an all-missing registration still lints")
end

T["re-registering replaces or clears a filetype rule"] = function()
  local first, second = 0, 0

  fake("sed", {
    cmd = function()
      return { "true" }
    end,
    parse = function()
      first = first + 1
      return {}
    end,
  })
  fake("sort", {
    cmd = function()
      return { "true" }
    end,
    parse = function()
      second = second + 1
      return {}
    end,
  })
  local bufnr = case("rereg", { "line" }, "sed")

  write(bufnr, dir .. "/rereg.txt")
  wait_for(function()
    return first >= 1
  end, "the first registration never linted")

  register({ filetypes = { "rereg" } }, "sort")
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr })
  wait_for(function()
    return second >= 1
  end, "the replacement registration never linted")
  assert(first == 1, "the replaced linter still runs")

  register({ filetypes = { "rereg" } }, {})
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr })
  spin(100)
  assert(second == 1, "an empty registration still lints")
end

T["map and sparse linter configurations are rejected"] = function()
  local invalid = {
    {
      name = "map top-level spec",
      lang = { filetypes = { "invalid-spec-map" } },
      spec = { linter = "sh" },
    },
    {
      name = "sparse top-level spec",
      lang = { filetypes = { "invalid-spec-sparse" } },
      spec = { [1] = "sh", [3] = "cat" },
    },
    {
      name = "non-string entry",
      lang = { filetypes = { "invalid-entry" } },
      spec = { "sh", 42 },
    },
    {
      name = "map filetypes",
      lang = { filetypes = { named = "invalid-filetype-map" } },
      spec = "sh",
    },
    {
      name = "sparse filetypes",
      lang = {
        filetypes = {
          [1] = "invalid-filetype-sparse-first",
          [3] = "invalid-filetype-sparse-third",
        },
      },
      spec = "sh",
    },
    {
      name = "non-string filetype",
      lang = { filetypes = { "invalid-filetype-string", 42 } },
      spec = "sh",
    },
  }

  for _, configuration in ipairs(invalid) do
    local ok = pcall(register, configuration.lang, configuration.spec)

    assert(not ok, configuration.name .. " was accepted")
  end
end

T["stdin linters receive the buffer text"] = function()
  local received = nil

  fake("head", {
    stdin = true,
    cmd = function()
      return { "cat" }
    end,
    parse = function(result)
      received = result.stdout
      return {}
    end,
  })
  local bufnr = case("stdin", { "alpha", "beta" }, "head")

  write(bufnr, dir .. "/stdin.txt")
  wait_for(function()
    return received ~= nil
  end, "the stdin linter never ran")
  assert(received == "alpha\nbeta", "stdin received: " .. vim.inspect(received))
end

T["a linter without cmd or parse fails loudly"] = function()
  fake("wc", { parse = function() end })
  fake("cut", {
    cmd = function()
      return { "true" }
    end,
  })

  local broken = {
    { name = "wc", filetype = "no-cmd" },
    { name = "cut", filetype = "no-parse" },
  }

  for _, linter in ipairs(broken) do
    local bufnr = case(linter.filetype, { "line" }, linter.name)

    vim.api.nvim_buf_set_name(bufnr, dir .. "/" .. linter.filetype .. ".txt")
    vim.v.errmsg = ""
    pcall(vim.api.nvim_exec_autocmds, "BufWritePost", { buffer = bufnr })

    assert(
      vim.v.errmsg ~= "" and vim.v.errmsg:find(linter.name, 1, true) ~= nil,
      ("linter %q broke without surfacing an error"):format(linter.name)
    )
  end
end

local function load_linter(name)
  local path = root .. "/src/lua/lang/linters/" .. name .. ".lua"
  local ok, linter = pcall(dofile, path)

  assert(ok, linter)
  assert(type(linter.cmd) == "function", name .. " must define cmd(ctx)")
  assert(
    type(linter.parse) == "function",
    name .. " must define parse(result, ctx)"
  )

  return linter
end

local function lint_file(linter, filename)
  local ctx = { bufnr = 0, filename = filename, cwd = dir }
  local result =
    vim.system(linter.cmd(ctx), { cwd = ctx.cwd, text = true }):wait()

  return linter.parse(result, ctx), ctx
end

T["selene findings become diagnostics"] = function()
  if vim.fn.executable("selene") ~= 1 then
    MiniTest.skip("selene is not installed")
  end

  local linter = load_linter("selene")
  local dirty = dir .. "/selene-dirty.lua"

  assert(vim.fn.writefile({ "local x = 1", "y = 2", "print(z)" }, dirty) == 0)
  local found, ctx = lint_file(linter, dirty)

  assert(#found == 4, "expected 4 diagnostics, got " .. #found)

  local undefined

  for _, diagnostic in ipairs(found) do
    if diagnostic.code == "undefined_variable" then
      undefined = diagnostic
    else
      assert(
        diagnostic.severity == vim.diagnostic.severity.WARN,
        "unexpected severity: " .. vim.inspect(diagnostic)
      )
    end
  end
  assert_diagnostic(undefined, {
    lnum = 2,
    col = 6,
    end_lnum = 2,
    end_col = 7,
    severity = vim.diagnostic.severity.ERROR,
    message = "`z` is not defined",
    code = "undefined_variable",
    source = "selene",
  }, "undefined_variable diagnostic")

  local clean = dir .. "/selene-clean.lua"

  assert(vim.fn.writefile({ "local x = 1", "return x" }, clean) == 0)
  assert(#lint_file(linter, clean) == 0, "a clean file produced diagnostics")

  local ok, garbage = pcall(
    linter.parse,
    { code = 1, signal = 0, stdout = "not json\n", stderr = "" },
    ctx
  )

  assert(ok, "garbage stdout raised: " .. tostring(garbage))
  assert(#garbage == 0, "garbage stdout produced diagnostics")
end

T["statix findings become diagnostics"] = function()
  if vim.fn.executable("statix") ~= 1 then
    MiniTest.skip("statix is not installed")
  end

  local linter = load_linter("statix")
  local dirty = dir .. "/statix-dirty.nix"

  assert(vim.fn.writefile({ "let in 1" }, dirty) == 0)
  local found, ctx = lint_file(linter, dirty)

  assert(#found == 1, "expected 1 diagnostic, got " .. #found)
  assert_diagnostic(found[1], {
    lnum = 0,
    col = 0,
    end_lnum = 0,
    end_col = 8,
    severity = vim.diagnostic.severity.WARN,
    message = "This let-in expression has no entries",
    code = "W02",
    source = "statix",
  }, "useless let-in diagnostic")

  local clean = dir .. "/statix-clean.nix"

  assert(vim.fn.writefile({ "let x = 1; in x" }, clean) == 0)
  assert(#lint_file(linter, clean) == 0, "a clean file produced diagnostics")

  local ok, garbage = pcall(
    linter.parse,
    { code = 1, signal = 0, stdout = "not json\n", stderr = "" },
    ctx
  )

  assert(ok, "garbage stdout raised: " .. tostring(garbage))
  assert(#garbage == 0, "garbage stdout produced diagnostics")
end

T["deadnix findings become diagnostics"] = function()
  if vim.fn.executable("deadnix") ~= 1 then
    MiniTest.skip("deadnix is not installed")
  end

  local linter = load_linter("deadnix")
  local dirty = dir .. "/deadnix-dirty.nix"

  assert(vim.fn.writefile({ "let", "  unused = 1;", "in 2" }, dirty) == 0)
  local found, ctx = lint_file(linter, dirty)

  assert(#found == 1, "expected 1 diagnostic, got " .. #found)
  assert_diagnostic(found[1], {
    lnum = 1,
    col = 2,
    end_lnum = 1,
    end_col = 8,
    severity = vim.diagnostic.severity.WARN,
    message = "Unused let binding: unused",
    source = "deadnix",
  }, "unused binding diagnostic")

  local clean = dir .. "/deadnix-clean.nix"

  assert(vim.fn.writefile({ "let x = 1; in x" }, clean) == 0)
  assert(#lint_file(linter, clean) == 0, "a clean file produced diagnostics")

  local ok, garbage = pcall(
    linter.parse,
    { code = 1, signal = 0, stdout = "not json\n", stderr = "" },
    ctx
  )

  assert(ok, "garbage stdout raised: " .. tostring(garbage))
  assert(#garbage == 0, "garbage stdout produced diagnostics")
end

return T
