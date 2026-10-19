-- Do-what-I-mean behaviour for <TAB>
local M = {}

local function snippet_active(direction)
  return vim.snippet
    and vim.snippet.active
    and vim.snippet.active({ direction = direction })
end

-- Insert / Select mode; priority is:
--   1. Completion menu
--   2. Active snippet
--   3. Literal Tab
local function insert_tab()
  if vim.fn.pumvisible() == 1 then
    return "<C-n>"
  end
  if snippet_active(1) then
    vim.schedule(function()
      vim.snippet.jump(1)
    end)
    return ""
  end
  return "<Tab>"
end

local function insert_backtab()
  if vim.fn.pumvisible() == 1 then
    return "<C-p>"
  end
  if snippet_active(-1) then
    vim.schedule(function()
      vim.snippet.jump(-1)
    end)
    return ""
  end
  return "<S-Tab>"
end

-- Normal mode; priority is:
--   1. Fold containing the cursor
--   2. Native <Tab> behaviour: jump-list forwards (<C-i>)

local function normal_tab()
  if vim.wo.foldenable and vim.fn.foldlevel(".") > 0 then
    return "za"
  end
  return "<C-i>"
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
