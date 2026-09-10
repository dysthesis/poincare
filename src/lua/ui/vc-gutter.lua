local M = {}

local ns = vim.api.nvim_create_namespace("git-gutter")

local state = {}

local signs = {
  add = {
    text = "│",
    hl = "GitGutterAdd",
  },
  change = {
    text = "│",
    hl = "GitGutterChange",
  },
  delete = {
    text = "_",
    hl = "GitGutterDelete",
  },
}

local function buffer_text(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, "\n")

  if vim.bo[buf].endofline then
    text = text .. "\n"
  end

  return text
end

local function sign(buf, line, kind)
  local spec = signs[kind]

  vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
    sign_text = spec.text,
    sign_hl_group = spec.hl,
  })
end

local function render(buf)
  local bufstate = state[buf]

  if not bufstate then
    return
  end

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local hunks =
    vim.text.diff(bufstate.base, buffer_text(buf), { result_type = "indices" })

  local nlines = vim.api.nvim_buf_line_count(buf)

  for _, hunk in ipairs(hunks) do
    local _, count_a, start_b, count_b = unpack(hunk)

    if count_a == 0 then
      -- Added lines.
      for line = start_b, start_b + count_b - 1 do
        sign(buf, line, "add")
      end
    elseif count_b == 0 then
      -- Deleted lines no longer exist, so mark the nearest
      -- surviving line.
      local line = math.max(1, math.min(start_b, nlines))
      sign(buf, line, "delete")
    else
      -- Changed lines.
      for line = start_b, start_b + count_b - 1 do
        sign(buf, line, "change")
      end
    end
  end
end

local function attach(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  if vim.bo[buf].buftype ~= "" then
    return
  end

  local path = vim.api.nvim_buf_get_name(buf)

  if path == "" then
    return
  end

  local root = vim.fs.root(path, ".git")

  if not root then
    return
  end

  local relative = vim.fs.relpath(root, path)

  if not relative then
    return
  end

  vim.system({ "git", "show", ":" .. relative }, {
    cwd = root,
    text = true,
  }, function(result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end

      if result.code ~= 0 then
        -- Not present in the index, e.g. an untracked file.
        state[buf] = nil
        vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
        return
      end

      state[buf] = {
        base = result.stdout or "",
      }

      render(buf)
    end)
  end)
end

function M.setup()
  vim.api.nvim_set_hl(0, "GitGutterAdd", {
    link = "DiffAdd",
  })

  vim.api.nvim_set_hl(0, "GitGutterChange", {
    link = "DiffChange",
  })

  vim.api.nvim_set_hl(0, "GitGutterDelete", {
    link = "DiffDelete",
  })
  local group = vim.api.nvim_create_augroup("git-gutter", {
    clear = true,
  })

  vim.api.nvim_create_autocmd({ "BufReadPost", "BufEnter", "FocusGained" }, {
    group = group,
    callback = function(event)
      attach(event.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function(event)
      render(event.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function(event)
      state[event.buf] = nil
    end,
  })
end

return M
