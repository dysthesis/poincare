-- Do-what-I-mean behaviour for <TAB>
local M = {}

local function rule(when, action)
  return {
    when = when,
    action = action,
  }
end

local function dispatch(rules, fallback)
  for _, candidate in ipairs(rules) do
    if candidate.when() then
      return candidate.action()
    end
  end

  return fallback()
end

local function key(lhs)
  return lhs
end

-- Completion
local function completion_visible()
  return vim.fn.pumvisible() == 1
end

local completion_next = rule(completion_visible, function()
  return "<C-n>"
end)

local completion_prev = rule(completion_visible, function()
  return "<C-p>"
end)

-- Snippets

local function snippet_active(direction)
  return vim.snippet
    and vim.snippet.active
    and vim.snippet.active({ direction = direction })
end

local snippet_next = rule(function()
  return snippet_active(1)
end, function()
  vim.schedule(function()
    vim.snippet.jump(1)
  end)

  return ""
end)

local snippet_prev = rule(function()
  return snippet_active(-1)
end, function()
  vim.schedule(function()
    vim.snippet.jump(-1)
  end)

  return ""
end)

-- Folds

local function in_fold()
  return vim.wo.foldenable and vim.fn.foldlevel(".") > 0
end

local toggle_fold = rule(in_fold, function()
  return "za"
end)

-- Insert / Select mode; priority is:
--   1. Completion menu
--   2. Active snippet
--   3. Literal Tab
local function insert_tab()
  return dispatch({
    completion_next,
    snippet_next,
  }, function()
    return "<Tab>"
  end)
end

local function insert_backtab()
  return dispatch({
    completion_prev,
    snippet_prev,
  }, function()
    return "<S-Tab>"
  end)
end

-- Normal mode; priority is:
--   1. Fold containing the cursor
--   2. Native <Tab> behaviour: jump-list forwards (<C-i>)

local function normal_tab()
  return dispatch({
    toggle_fold,
  }, function()
    return "<C-i>"
  end)
end

local function normal_backtab()
  -- opposite of <C-i>, move backwards through the jump list
  return "<C-o>"
end

function M.setup()
  vim.keymap.set({ "i", "s" }, "<Tab>", insert_tab, {
    expr = true,
    silent = true,
    desc = "DWIM Tab",
  })

  vim.keymap.set({ "i", "s" }, "<S-Tab>", insert_backtab, {
    expr = true,
    silent = true,
    desc = "DWIM Shift-Tab",
  })

  vim.keymap.set("n", "<Tab>", normal_tab, {
    expr = true,
    silent = true,
    desc = "DWIM Tab",
  })

  vim.keymap.set("n", "<S-Tab>", normal_backtab, {
    expr = true,
    silent = true,
    desc = "Jump backwards",
  })
end

return M
