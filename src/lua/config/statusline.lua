-- Originally from:
-- https://github.com/shivambegin/Neovim/blob/a1b6009501f88dcc82d4fc681bb28dc2ab781d77/lua/config/statusline.lua
local statusline_bg = '#080808' -- Dark blue background (adjust to your preference)

-- Set the default StatusLine highlight group
vim.api.nvim_set_hl(0, 'StatusLine', {
  fg = '#ffffff', -- Default text color
  bg = statusline_bg,
})

-- Set StatusLineNC (non-current statusline) to match
vim.api.nvim_set_hl(0, 'StatusLineNC', {
  fg = '#565f89', -- Dimmer text for inactive statuslines
  bg = statusline_bg,
})

-- Now set all your custom statusline highlight groups to use the same background
vim.api.nvim_set_hl(0, 'StatusLineModeBold', {
  fg = '#ffffff', -- Mode text color
  bg = statusline_bg,
  bold = true,
})

vim.api.nvim_set_hl(0, 'StatusLineMode', {
  fg = '#ffffff',
  bg = statusline_bg,
})

vim.api.nvim_set_hl(0, 'StatusLineMedium', {
  fg = '#444444',
  bg = statusline_bg,
})
local statusline_augroup = vim.api.nvim_create_augroup('native_statusline', { clear = true })

--- @return string
local function filename()
  local fname = vim.fn.expand('%:t')
  if fname == '' then
    return ''
  end
  return fname .. ' '
end

local modes = {
  ['n'] = 'NOR',
  ['no'] = 'NOR',
  ['v'] = 'VIS',
  ['V'] = 'VISUAL LINE',
  [''] = 'VISUAL BLOCK',
  ['s'] = 'SEL',
  ['S'] = 'SELECT LINE',
  [''] = 'SELECT BLOCK',
  ['i'] = 'INS',
  ['ic'] = 'INS',
  ['R'] = 'REPLACE',
  ['Rv'] = 'VISUAL REPLACE',
  ['c'] = 'COMMAND',
  ['cv'] = 'VIM EX',
  ['ce'] = 'EX',
  ['r'] = 'PROMPT',
  ['rm'] = 'MOAR',
  ['r?'] = 'CONFIRM',
  ['!'] = 'SHELL',
  ['t'] = 'TERMINAL',
}
--- @return string
local function mode()
  local current_mode = vim.api.nvim_get_mode().mode
  return string.format('%%#StatusLineModeBold# %s %%*', modes[current_mode]):upper()
end

--- @return string
local function file_percentage()
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_line_count(0)

  return string.format('%%#StatusLineMedium#  %d%%%% %%*', math.ceil(current_line / lines * 100))
end

--- @return string
local function total_lines()
  local row = vim.fn.line('.')
  local col = vim.fn.col('.')
  local total = vim.fn.line('$')
  return string.format('%%#StatusLineMedium#%d:%d of %d %%*', row, col, total)
end

--- @param hlgroup string
local function formatted_filetype(hlgroup)
  local filetype = vim.bo.filetype or vim.fn.expand('%:e', false)
  return string.format('%%#%s# %s %%*', hlgroup, filetype)
end

local function filetype()
  local filetype = vim.bo.filetype or vim.fn.expand('%:e', false)
  return string.format(' %%#StatuslineTitle#%s', filetype)
end

StatusLine = {}

StatusLine.inactive = function()
  return table.concat {
    formatted_filetype('StatusLineMode'),
  }
end

local redeable_filetypes = {
  ['qf'] = true,
  ['help'] = true,
  ['tsplayground'] = true,
}

StatusLine.active = function()
  local mode_str = vim.api.nvim_get_mode().mode
  if mode_str == 't' or mode_str == 'nt' then
    return table.concat {
      mode(),
      '%=',
      '%=',
      file_percentage(),
      total_lines(),
    }
  end

  if redeable_filetypes[vim.bo.filetype] or vim.o.modifiable == false then
    return table.concat {
      formatted_filetype('StatusLineMode'),
      '%=',
      '%=',
      file_percentage(),
      total_lines(),
    }
  end

  local statusline = {
    mode(),
    filename(),
    '%=',
    '%=',
    file_percentage(),
    total_lines(),
    filetype(),
  }

  return table.concat(statusline)
end

vim.opt.statusline = '%!v:lua.StatusLine.active()'

vim.api.nvim_create_autocmd({ 'WinEnter', 'BufEnter', 'FileType' }, {
  group = statusline_augroup,
  pattern = {
    'NvimTree_1',
    'NvimTree',
    'TelescopePrompt',
    'fzf',
    'lspinfo',
    'lazy',
    'netrw',
    'mason',
    'noice',
    'qf',
  },
  callback = function()
    vim.opt_local.statusline = '%!v:lua.StatusLine.inactive()'
  end,
})
