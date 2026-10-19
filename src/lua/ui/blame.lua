--- Current-line blame for the pinned Neovim 0.13 nightly.
--- Uses unsaved buffer contents and active-window, right-aligned virtual text.
--- GitBlame styles the entire annotation; :GitBlame forces a refresh.
local M = {}

local ns = vim.api.nvim_create_namespace("git_blame")
local request

local function clear()
  local previous = request
  request = nil
  if not previous then
    return
  end

  if previous.timer and not previous.timer:is_closing() then
    previous.timer:stop()
    previous.timer:close()
  end
  if previous.process and not previous.process:is_closing() then
    previous.process:kill(15)
  end
  if vim.api.nvim_buf_is_valid(previous.buf) then
    vim.api.nvim_buf_clear_namespace(previous.buf, ns, 0, -1)
  end
end

local function is_current(current)
  return current ~= nil
    and request == current
    and vim.api.nvim_buf_is_valid(current.buf)
    and vim.api.nvim_get_current_buf() == current.buf
    and vim.api.nvim_get_current_win() == current.win
    and vim.api.nvim_win_get_cursor(current.win)[1] == current.row
    and vim.api.nvim_buf_get_name(current.buf) == current.path
    and vim.bo[current.buf].buftype == ""
    and vim.api.nvim_buf_get_changedtick(current.buf) == current.tick
end

local function format_blame(output)
  local hash = output:match("^(%x+) ")
  if not hash then
    return
  end
  if hash:match("^0+$") then
    return { { "  Not committed yet", "GitBlame" } }
  end

  local author = output:match("\nauthor ([^\n]+)")
  local timestamp = tonumber(output:match("\nauthor%-time (%-?%d+)"))
  local summary = output:match("\nsummary ([^\n]*)")
  if not (author and timestamp and summary) then
    return
  end

  -- Commit metadata can contain tabs and other control characters.
  author = author:gsub("%c", " ")
  summary = summary:gsub("%c", " ")
  return {
    {
      string.format(
        "  %s · %s · %s — %s",
        author,
        os.date("%Y-%m-%d", timestamp),
        hash:sub(1, 8),
        summary
      ),
      "GitBlame",
    },
  }
end

function M.blame_line()
  clear()

  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or vim.bo[buf].buftype ~= "" then
    return
  end

  local current = {
    buf = buf,
    win = win,
    path = path,
    row = vim.api.nvim_win_get_cursor(win)[1],
    tick = vim.api.nvim_buf_get_changedtick(buf),
  }
  request = current

  current.timer = vim.defer_fn(function()
    current.timer = nil
    if not is_current(current) then
      return
    end

    local newline = vim.bo[buf].fileformat == "dos" and "\r\n" or "\n"
    local contents =
      table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), newline)
    if
      contents == ""
      and vim.api.nvim_buf_call(buf, function()
          return vim.fn.wordcount().bytes
        end)
        == 0
    then
      return
    end
    if vim.bo[buf].endofline then
      contents = contents .. newline
    end

    -- Blame the buffer snapshot, not the possibly older file on disk.
    local started, process = pcall(vim.system, {
      "git",
      "blame",
      "--porcelain",
      "--contents",
      "-",
      "-L",
      current.row .. ",+1",
      "--",
      vim.fs.basename(path),
    }, {
      cwd = vim.fs.dirname(path),
      stdin = contents,
      text = true,
    }, function(result)
      vim.schedule(function()
        current.process = nil
        if result.code ~= 0 or not is_current(current) then
          return
        end

        local chunks = format_blame(result.stdout or "")
        if not chunks then
          return
        end

        -- A buffer can be visible in several splits; only decorate this one.
        vim.api.nvim__ns_set(ns, { wins = { win } })
        vim.api.nvim_buf_set_extmark(buf, ns, current.row - 1, 0, {
          virt_text = chunks,
          virt_text_pos = "eol_right_align",
          hl_mode = "combine",
          priority = 1,
        })
      end)
    end)
    if started then
      current.process = process
    end
  end, 150)
end

local function highlights()
  vim.api.nvim_set_hl(0, "GitBlame", {
    default = true,
    fg = "#737373",
    ctermfg = 243,
  })
end

function M.setup()
  clear()
  highlights()
  local group = vim.api.nvim_create_augroup("GitBlame", {
    clear = true,
  })

  vim.api.nvim_create_autocmd({
    "CursorMoved",
    "CursorMovedI",
    "BufEnter",
    "WinEnter",
    "BufReadPost",
    "BufWritePost",
    "BufFilePost",
    "TextChanged",
    "TextChangedI",
    "TextChangedP",
    "FocusGained",
  }, {
    group = group,
    callback = function(args)
      if args.buf ~= vim.api.nvim_get_current_buf() then
        return
      end
      if
        (args.event == "CursorMoved" or args.event == "CursorMovedI")
        and is_current(request)
      then
        return
      end
      M.blame_line()
    end,
  })

  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = { "buftype", "endofline", "fileformat" },
    callback = M.blame_line,
  })

  vim.api.nvim_create_autocmd({
    "BufLeave",
    "WinLeave",
    "BufUnload",
    "BufWipeout",
  }, {
    group = group,
    callback = function(args)
      if request and request.buf == args.buf then
        clear()
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = clear,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = highlights,
  })

  vim.api.nvim_create_user_command("GitBlame", M.blame_line, {
    desc = "Refresh Git blame for the current buffer line",
  })

  vim.schedule(M.blame_line)
end

return M
