local M = {}

function M.run(root, ...)
  local args = { "git", "-C", root, ... }
  local result = assert(vim.system(args, { text = true }):wait(3000))
  assert(
    result.code == 0,
    ("%s: %s"):format(table.concat(args, " "), result.stderr or "")
  )
  return result.stdout or ""
end

function M.write(path, text)
  local file = assert(io.open(path, "wb"))
  assert(file:write(text))
  assert(file:close())
end

function M.read(path)
  local file = assert(io.open(path, "rb"))
  local text = assert(file:read("a"))
  assert(file:close())
  return text
end

function M.signs(buf)
  local ns = assert(
    vim.api.nvim_get_namespaces()["git-gutter"],
    "gutter namespace missing"
  )
  local signs = {}
  for _, mark in
    ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }))
  do
    if mark[4].sign_hl_group then
      signs[#signs + 1] = mark[4].sign_hl_group
    end
  end
  return signs
end

return M
