local M = {}
local function get_shell()
  local sh = vim.o.shell ~= '' and vim.o.shell or '/bin/sh'
  local flag = vim.o.shellcmdflag ~= '' and vim.o.shellcmdflag or '-c'
  assert(vim.fn.executable(sh) == 1, 'No usable shell found')
  return sh, flag
end

function M.open(subdir)
  local title = ''
  local prompt = 'New note title: '
  if subdir then
    prompt = 'New note in ' .. subdir .. ': '
  end
  vim.ui.input({ prompt = prompt }, function(input)
    if input then
      title = input
    else
      vim.notify('No title was provided!', vim.log.levels.WARN)
      return
    end
  end)
  local new_note_cmd = 'zk new --print-path --title "' .. title .. '"'
  if subdir then
    new_note_cmd = new_note_cmd .. ' ' .. subdir
  end
  local path = vim.fn.system(new_note_cmd)
  vim.cmd('edit ' .. path)
end
return M
