local M = {}

M.config = {
  picker_cmd =
    -- We get ripgrep to
    -- - emit only the paths that it would search (`--files`),
    -- - include any hidden files or directories (`--hidden`),
    -- - follow symbolic links (`follow`), and
    -- - ignore any file under `.git` (`--glob '!.git/*'`)...
    'rg '
    .. '--files '
    .. '--hidden '
    .. '--follow '
    .. "--glob '!.git/*' "
    -- ...and then we pipe it to...
    .. '|'
    -- ...fzf, which
    -- - accepts ANSI colour codes (`--ansi`),
    -- - aceepts multiple selections (`--multi`),
    -- - maps Ctrl-A to select every entry (`--bind 'ctrl-a:select-all'`),
    -- - maps Ctrl-V to open the new file in a vsplit (`--expect ctrl-v`),
    -- - delimits the output with NUL instead of newline (`--print0`)
    -- - and previews the files with `bat` (`--preview 'bat --style=numbers --color=always`)>
    .. 'fzf '
    .. '--ansi '
    .. '--multi '
    .. "--bind 'ctrl-a:select-all' "
    .. '--expect ctrl-v '
    .. '--no-clear '
    .. "--preview 'bat --style=numbers --color=always {}' "
    .. '--preview-window=right:75%:wrap',
}
-- Open a new window
local function open_split(buf, opts)
  local caller = vim.api.nvim_get_current_win()
  vim.cmd(opts.side == 'top' and 'topleft split' or 'botright split')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  if opts.height then
    local rows = math.floor(vim.o.lines * opts.height)
    vim.api.nvim_win_set_option(win, 'winfixheight', true)
    vim.api.nvim_win_set_height(win, rows)
  end
  return win, caller
end

local function get_shell_and_flag()
  local sh = vim.o.shell
  local flag = vim.o.shellcmdflag
  if not sh or sh == '' then
    sh = '/bin/sh'
  end
  if not flag or flag == '' then
    flag = '-c'
  end
  -- refuse to launch if the shell itself is missing
  if vim.fn.executable(sh) == 0 then
    vim.notify(string.format('fzf-picker: shell %q not found‼', sh), vim.log.levels.ERROR)
    return nil
  end
  return sh, flag
end

function M.open()
  -- Ensure we have a valid shell & flag
  local shell, flag = get_shell_and_flag()
  if not shell then
    return
  end -- abort early if even /bin/sh missing

  -- Prepare buffer + horizontal split
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  local term_win, caller_win = open_split(buf, { height = 0.35, side = 'bottom' })
  vim.api.nvim_set_current_win(term_win)

  -- Build a single string; avoids the nil-element problem
  local full_cmd = string.format('%s %s "%s"', shell, flag, M.config.picker_cmd)

  vim.fn.termopen(full_cmd, {
    on_exit = function(job, code, signal)
      vim.schedule(function()
        M._on_exit(buf, term_win, caller_win, job, code, signal)
      end)
    end,
  })

  vim.schedule(function()
    vim.cmd('startinsert')
  end)
end

function M._on_exit(buf, term_win, caller_win, job, code, _signal)
  -- harvest the tail of the scroll-back (unchanged)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local results = {}
  for i = #lines, 1, -1 do
    local l = vim.trim(lines[i])
    if l == '' and #results == 0 then
      goto continue
    elseif l == '' then
      break
    end
    table.insert(results, 1, l)
    ::continue::
  end
  if vim.tbl_isempty(results) then
    return
  end

  -- split key / paths (unchanged)
  local key = (results[1] == 'ctrl-v') and table.remove(results, 1) or ''
  local opener = ({ ['ctrl-v'] = 'vsplit' })[key] or 'edit'

  -- Close the terminal window, jump back, then open
  if vim.api.nvim_win_is_valid(term_win) then
    vim.api.nvim_win_close(term_win, true) -- remove picker split
  end
  if vim.api.nvim_win_is_valid(caller_win) then
    vim.api.nvim_set_current_win(caller_win) -- focus caller
  end

  for _, path in ipairs(results) do -- open files normally
    vim.cmd(opener .. ' ' .. vim.fn.fnameescape(path))
  end
end

function M.setup(user_opts)
  M.config = vim.tbl_deep_extend('force', M.config, user_opts or {})
  vim.keymap.set('n', '<leader>f', M.open, { desc = 'FZF file picker' })
end

return M
