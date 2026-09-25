local MiniTest = require("mini.test")
local test_file = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local root = vim.fs.dirname(vim.fs.dirname(test_file))
local diagnostic = dofile(root .. "/src/lua/ui/statusline/diagnostic.lua")
local original_count = vim.diagnostic.count
local original_clients = vim.lsp.get_clients
local saved_highlights
local groups = {
  "StatusLine",
  "Conceal",
  "DiagnosticError",
  "DiagnosticWarn",
  "DiagnosticInfo",
  "DiagnosticHint",
  "StatusLineError",
  "StatusLineWarn",
  "StatusLineInfo",
  "StatusLineHint",
  "StatusLineLsp",
}

local T = MiniTest.new_set({
  hooks = {
    pre_each = function()
      saved_highlights = {}
      for _, group in ipairs(groups) do
        saved_highlights[group] =
          vim.api.nvim_get_hl(0, { name = group, link = true })
      end
      vim.diagnostic.count = function()
        return {}
      end
      vim.lsp.get_clients = function()
        return {}
      end
    end,
    post_each = function()
      vim.diagnostic.count = original_count
      vim.lsp.get_clients = original_clients
      for group, attrs in pairs(saved_highlights) do
        vim.api.nvim_set_hl(0, group, attrs)
      end
    end,
  },
})

local function counts(values)
  vim.diagnostic.count = function(bufnr)
    assert(bufnr == 0)
    return values
  end
end

local function clients(values)
  vim.lsp.get_clients = function(opts)
    assert(opts.bufnr == 0)
    return values
  end
end

local function equal(actual, expected)
  assert(
    actual == expected,
    ("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual))
  )
end

T["all severity references, glyphs, counts and order"] = function()
  counts({ [1] = 2, [2] = 3, [3] = 4, [4] = 5 })
  equal(
    diagnostic.component(),
    "%#StatusLineError# 2 %#StatusLineWarn# 3 %#StatusLineInfo# 4 %#StatusLineHint#󰌵 5"
  )
end

T["zero, missing and empty counts omit segments"] = function()
  counts({ [1] = 0, [2] = 10, [4] = 0 })
  equal(diagnostic.component(), "%#StatusLineWarn# 10")
  counts({})
  equal(diagnostic.component(), "")
end

T["Lsp has its own reference and sorted client names"] = function()
  equal(diagnostic.component(), "")
  clients({ { name = "zeta" }, { name = "alpha" } })
  equal(diagnostic.component(), "%#StatusLineLsp# alpha,zeta")
  counts({ [3] = 1 })
  equal(
    diagnostic.component(),
    "%#StatusLineLsp# alpha,zeta %#StatusLineInfo# 1"
  )
end

local sources = {
  StatusLine = { bg = 0x123456 },
  Conceal = { fg = 0x234567 },
  DiagnosticError = { fg = 0x345678 },
  DiagnosticWarn = { fg = 0x456789 },
  DiagnosticInfo = { fg = 0x56789a },
  DiagnosticHint = { fg = 0x6789ab },
}

local function source_highlights()
  for group, attrs in pairs(sources) do
    vim.api.nvim_set_hl(0, group, attrs)
  end
end

local function assert_highlights()
  for name, fg in pairs({
    StatusLineError = 0x345678,
    StatusLineWarn = 0x456789,
    StatusLineInfo = 0x56789a,
    StatusLineHint = 0x6789ab,
    StatusLineLsp = 0x234567,
  }) do
    local actual = vim.api.nvim_get_hl(0, { name = name, link = false })
    equal(actual.fg, fg)
    equal(actual.bg, 0x123456)
  end
end

T["setup defines severity and Lsp highlights from source groups"] = function()
  source_highlights()
  package.loaded["ui.statusline"] = nil
  require("ui.statusline")
  assert_highlights()
end

T["target overrides are immediate but set_hl_groups reapplies sources"] = function()
  local statusline = require("ui.statusline")
  source_highlights()
  statusline.set_hl_groups()
  vim.api.nvim_set_hl(0, "StatusLineError", { fg = 0xabcdef, bg = 0xfedcba })
  local overridden =
    vim.api.nvim_get_hl(0, { name = "StatusLineError", link = false })
  equal(overridden.fg, 0xabcdef)
  equal(overridden.bg, 0xfedcba)
  statusline.set_hl_groups()
  assert_highlights()
end

T["ColorScheme reapplies source highlights over direct overrides"] = function()
  local statusline = require("ui.statusline")
  source_highlights()
  statusline.set_hl_groups()
  vim.api.nvim_set_hl(0, "StatusLineError", { fg = 0xabcdef })
  vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "diagnostic-test" })
  assert_highlights()
end

return T
