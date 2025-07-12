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

local function get_shell()
  local sh = vim.o.shell ~= '' and vim.o.shell or '/bin/sh'
  local flag = vim.o.shellcmdflag ~= '' and vim.o.shellcmdflag or '-c'
  assert(vim.fn.executable(sh) == 1, 'No usable shell found')
  return sh, flag
end

-- producer: shell string that generates lines for fzf
-- preview: (optional) fzf --preview string
-- extra: (optional) extra fzf flags (string)
-- parse: function(list_of_lines) -> lua_table
-- sink: function(lua_table, key) – side-effect
function M.run(spec)
  local shell, flag = get_shell() -- guard against v:null
  local caller = vim.api.nvim_get_current_win()
  local buf, term = open_split(0.35) -- winfixheight split

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
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local out, seen = {}, false
        for i = #lines, 1, -1 do
          local l = vim.trim(lines[i])
          if l ~= '' then
            seen = true
          end
          if seen then
            table.insert(out, 1, l)
          end
          if seen and l == '' then
            break
          end
        end

        -- always return focus to caller before closing split
        if vim.api.nvim_win_is_valid(caller) then
          vim.api.nvim_set_current_win(caller)
        end
        if vim.api.nvim_win_is_valid(term) then
          vim.api.nvim_win_close(term, true) 
        end
        vim.cmd('redraw')

        if exit_code ~= 0 or not next(out) then 
          return
        end

        -- normal path; parse key and open files
        local key = (out[1] == 'ctrl-v') and table.remove(out, 1) or ''
        spec.sink(spec.parse(out), key)
      end)
    end,
  })
  vim.schedule(function()
    vim.cmd('startinsert')
  end)
end

return M
