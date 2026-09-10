local M = {}

local pinned = {}

local function prune()
  for i = #pinned, 1, -1 do
    if not vim.api.nvim_buf_is_valid(pinned[i]) then
      table.remove(pinned, i)
    end
  end
end

function M.toggle()
  prune()

  local buf = vim.api.nvim_get_current_buf()

  for i, pinned_buf in ipairs(pinned) do
    if pinned_buf == buf then
      table.remove(pinned, i)
      return
    end
  end

  if #pinned < 10 then
    pinned[#pinned + 1] = buf
  end
end

function M.select(i)
  prune()

  local buf = pinned[i]

  if buf then
    vim.api.nvim_set_current_buf(buf)
  end
end

function M.show()
  if #pinned == 0 then
    vim.notify("No pinned buffers")
    return
  end

  local lines = {}

  for i, buf in ipairs(pinned) do
    local path = vim.api.nvim_buf_get_name(buf)

    if path == "" then
      path = "[No Name]"
    else
      path = vim.fn.fnamemodify(path, ":~:.")
    end

    lines[#lines + 1] = ("%d: %s"):format(i, path)
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
