local M = {}

local pinned = {}

local function prune()
  for i = #pinned, 1, -1 do
    if not vim.api.nvim_buf_is_valid(pinned[i]) then
      table.remove(pinned, i)
    end
  end
end

local function current_path()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    return nil
  end

  return vim.fs.normalize(path)
end

function M.toggle()
  local path = current_path()

  if not path then
    return
  end

  for i, pinned_path in ipairs(pinned) do
    if pinned_path == path then
      table.remove(pinned, i)
      M.save()
      return
    end
  end

  if #pinned < 10 then
    pinned[#pinned + 1] = path
    M.save()
  end
end

function M.select(i)
  local path = pinned[i]

  if path then
    vim.cmd.edit(vim.fn.fnameescape(path))
  end
end

function M.show()
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

local state_dir = vim.fs.joinpath(vim.fn.stdpath("state"), "pins")

local function project()
  return vim.fs.root(0, ".git") or vim.fn.getcwd()
end

local function state_file()
  local root = project()
  if not root then
    return nil
  end

  local hash = vim.fn.sha256(vim.fs.normalize(root))
  return vim.fs.joinpath(state_dir, hash .. ".json")
end

function M.save()
  local path = state_file()
  if not path then
    return
  end

  vim.fn.mkdir(state_dir, "p")

  vim.fn.writefile({ vim.json.encode(pinned) }, path)
end

function M.load()
  local path = state_file()
  if not path or vim.fn.filereadable(path) == 0 then
    pinned = {}
    return
  end

  local text = table.concat(vim.fn.readfile(path), "\n")
  local ok, val = pcall(vim.json.decode, text)
  pinned = ok and type(val) == "table" and val or {}
end

function M.setup()
  M.load()
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
