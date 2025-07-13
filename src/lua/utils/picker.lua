local M = {}

-- base command that every picker inherits;
local BASE_FZF = table.concat({
  'fzf',
  -- allow ANSI colour code
  '--ansi',
  -- allow multiple selections
  '--multi',
  -- enter Ctrl-A to select everything
  "--bind 'ctrl-a:select-all'",
  '--expect ctrl-v',
  '--no-clear',
}, ' ')

-- Helper function to open a split menu. It takes in
--
-- - `height_pct`, which is the height of the popup buffer to open in percent.`
local function open_split(height_pct)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.cmd('botright split')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_option(win, 'winfixheight', true)
  vim.api.nvim_win_set_height(win, math.floor(vim.o.lines * height_pct))
  return buf, win
end

-- Helper function to find the shell in the system
local function get_shell()
  local sh = vim.o.shell ~= '' and vim.o.shell or '/bin/sh'
  local flag = vim.o.shellcmdflag ~= '' and vim.o.shellcmdflag or '-c'
  assert(vim.fn.executable(sh) == 1, 'No usable shell found')
  return sh, flag
end

-- Runs the fuzzy finder menu. This function takes in a spec containing
--
-- - `producer`, which is a shell string that generates lines for `fzf`,
-- - `preview`, which is an optional `fzf --preview` string,
-- - `extra`, which is an optional extra `fzf` flags (string),
-- - `parse`, which si a function that parses the menu options into a Lua table, and
-- - `sink`, which is a function that takes the Lua table produced by `parse` and performs some
--   action with it.
function M.run(spec)
  local shell, flag = get_shell() -- guard against v:null
  local caller = vim.api.nvim_get_current_win()
  local buf, term = open_split(0.25) -- winfixheight split

  -- build full fzf pipeline once
  local fzf_cmd = BASE_FZF
  if spec.preview then
    fzf_cmd = fzf_cmd .. ' --preview ' .. vim.fn.shellescape(spec.preview)
  end
  if spec.extra then
    fzf_cmd = fzf_cmd .. ' ' .. spec.extra
  end

  local pipeline = spec.producer .. ' | ' .. fzf_cmd

  vim.fn.termopen({ shell, flag, pipeline }, {
    on_exit = function(_, exit_code, _)
      vim.schedule(function()
        if exit_code ~= 0 then
          -- Close the window and do nothing on non-zero exit (e.g., user pressed Esc)
          if vim.api.nvim_win_is_valid(caller) then
            vim.api.nvim_set_current_win(caller)
          end
          if vim.api.nvim_win_is_valid(term) then
            vim.api.nvim_win_close(term, true)
          end
          vim.cmd('redraw')
          return
        end

        -- Get all lines from the buffer and filter out any empty ones.
        local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

        local out = vim.tbl_filter(function(v)
          return v ~= ''
        end, all_lines)

        -- always return focus to caller before closing split
        if vim.api.nvim_win_is_valid(caller) then
          vim.api.nvim_set_current_win(caller)
        end
        if vim.api.nvim_win_is_valid(term) then
          vim.api.nvim_win_close(term, true)
        end
        vim.cmd('redraw')

        -- If there's no output, we're done.
        if not next(out) then
          return
        end

        -- normal path; parse key and open files
        local key = ''
        if out[1] == 'ctrl-v' then
          key = table.remove(out, 1)
        end
        -- Don't process if the only thing returned was the key (i.e., no selections)
        if not next(out) then
          return
        end
        local parsed = spec.parse(out)
        spec.sink(parsed, key)
      end)
    end,
  })
  vim.schedule(function()
    vim.cmd('startinsert')
  end)
end

return M
