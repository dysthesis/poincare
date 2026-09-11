local M = {}

local state_dir = vim.fs.joinpath(vim.fn.stdpath("state"), "pins")

-- Project root -> pinned paths.
local projects = {}

local function current_path()
  local path = vim.api.nvim_buf_get_name(0)

  if path == "" then
    return nil
  end

  return vim.fs.normalize(path)
end

local function project()
  local root = vim.fs.root(0, ".git") or vim.fn.getcwd()

  return vim.fs.normalize(root)
end

local function state_file(root)
  local hash = vim.fn.sha256(root)

  return vim.fs.joinpath(state_dir, hash .. ".json")
end

local function load(root)
  if projects[root] then
    return projects[root]
  end

  local path = state_file(root)

  if vim.fn.filereadable(path) == 0 then
    projects[root] = {}
    return projects[root]
  end

  local text = table.concat(vim.fn.readfile(path), "\n")
  local ok, value = pcall(vim.json.decode, text)

  if not ok or type(value) ~= "table" then
    value = {}
  end

  projects[root] = value

  return projects[root]
end

local function save(root, pinned)
  vim.fn.mkdir(state_dir, "p")

  vim.fn.writefile({
    vim.json.encode(pinned),
  }, state_file(root))
end

local function current()
  local root = project()

  return root, load(root)
end

function M.toggle()
  local path = current_path()

  if not path then
    return
  end

  local root, pinned = current()

  for i, pinned_path in ipairs(pinned) do
    if pinned_path == path then
      table.remove(pinned, i)
      save(root, pinned)
      return
    end
  end

  if #pinned < 10 then
    pinned[#pinned + 1] = path
    save(root, pinned)
  end
end

function M.select(i)
  local _, pinned = current()
  local path = pinned[i]

  if path then
    vim.cmd.edit(vim.fn.fnameescape(path))
  end
end

function M.show()
  local _, pinned = current()

  if #pinned == 0 then
    vim.notify("No pinned buffers")
    return
  end

  local lines = {}

  for i, path in ipairs(pinned) do
    lines[#lines + 1] = ("%d: %s"):format(i, vim.fn.fnamemodify(path, ":~:."))
  end

  vim.notify(table.concat(lines, "\n"))
end

function M.setup()
  vim.keymap.set("n", "<leader>h", M.toggle)

  for i = 1, 9 do
    vim.keymap.set("n", "<leader>" .. i, function()
      M.select(i)
    end)
  end

  vim.keymap.set("n", "<leader>p", M.show, {
    desc = "Show pinned buffers",
  })

  vim.keymap.set("n", "<leader>0", function()
    M.select(10)
  end)
end

return M
