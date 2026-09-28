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

  if
    vim.bo[buf].endofline
    and (
      text ~= ""
      or vim.api.nvim_buf_call(buf, function()
          -- Unlike visible { "" }, this distinguishes zero bytes from one LF.
          return vim.fn.wordcount().bytes
        end)
        > 0
    )
  then
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

local function detach(buf)
  state[buf] = nil
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
end
local function render(buf)
  local bufstate = state[buf]

  if not bufstate then
    return
  end
  if vim.bo[buf].buftype ~= "" then
    detach(buf)
    return
  end
  if bufstate.base == nil then
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
    state[buf] = nil
    return
  end

  local path = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype ~= "" or path == "" then
    detach(buf)
    return
  end

  local root = vim.fs.root(path, ".git")
  local relative = root and vim.fs.relpath(root, path)
  if not relative then
    detach(buf)
    return
  end

  local previous = state[buf]
  local same_file = previous and previous.path == path and previous.root == root
  local request = {
    path = path,
    root = root,
    base = same_file and previous.base or nil,
  }
  if not same_file then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
  state[buf] = request

  local started = pcall(vim.system, { "git", "show", ":" .. relative }, {
    cwd = root,
    text = true,
  }, function(result)
    vim.schedule(function()
      if state[buf] ~= request or not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      if
        vim.bo[buf].buftype ~= ""
        or vim.api.nvim_buf_get_name(buf) ~= path
        or vim.fs.root(path, ".git") ~= root
      then
        detach(buf)
        return
      end

      if result.code ~= 0 then
        -- Not present in the index, e.g. an untracked file.
        detach(buf)
        return
      end

      request.base = result.stdout or ""
      render(buf)
    end)
  end)
  if
    not started
    and state[buf] == request
    and vim.api.nvim_buf_is_valid(buf)
  then
    detach(buf)
  end
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

  vim.api.nvim_create_autocmd({
    "BufReadPost",
    "BufEnter",
    "BufFilePost",
    "FocusGained",
  }, {
    group = group,
    callback = function(event)
      attach(event.buf)
    end,
  })

  vim.api.nvim_create_autocmd({
    "TextChanged",
    "TextChangedI",
    "BufWritePost",
  }, {
    group = group,
    callback = function(event)
      render(event.buf)
    end,
  })

  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = "endofline",
    callback = function()
      render(vim.api.nvim_get_current_buf())
    end,
  })

  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = "buftype",
    callback = function()
      attach(vim.api.nvim_get_current_buf())
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(event)
      detach(event.buf)
    end,
  })
end

return M
