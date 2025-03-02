-- Originally from:
-- https://github.com/shivambegin/Neovim/blob/a1b6009501f88dcc82d4fc681bb28dc2ab781d77/lua/config/statusline.lua

local statusline_augroup = vim.api.nvim_create_augroup('native_statusline', { clear = true })

local function setup_highlights()
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

  vim.api.nvim_set_hl(0, 'StatusLineLspActive', {
    fg = '#789978',
    bg = statusline_bg,
  })

  vim.api.nvim_set_hl(0, 'StatusLineLspError', {
    fg = '#ffaa88',
    bg = statusline_bg,
  })

  vim.api.nvim_set_hl(0, 'StatusLineLspWarn', {
    fg = '#ffaa88',
    bg = statusline_bg,
  })

  vim.api.nvim_set_hl(0, 'StatusLineLspHint', {
    fg = '#7788aa',
    bg = statusline_bg,
  })

  vim.api.nvim_set_hl(0, 'StatusLineLspInfo', {
    fg = '#0db9d7',
    bg = statusline_bg,
  })

  vim.api.nvim_set_hl(0, 'StatusLineLspMessages', {
    fg = '#a9b1d6',
    bg = statusline_bg,
  })

  vim.api.nvim_set_hl(0, 'StatusLineGitDiffAdded', {
    fg = '#789978',
    bg = statusline_bg,
  })

  vim.api.nvim_set_hl(0, 'StatusLineGitDiffChanged', {
    fg = '#708090',
    bg = statusline_bg,
  })

  vim.api.nvim_set_hl(0, 'StatusLineGitDiffRemoved', {
    fg = '#ffaa88',
    bg = statusline_bg,
  })

  vim.api.nvim_set_hl(0, 'StatusLineGitBranchIcon', {
    fg = '#444444',
    bg = statusline_bg,
  })
end

-- Create an autocommand to ensure highlights are updated when colorscheme changes
vim.api.nvim_create_autocmd('ColorScheme', {
  group = statusline_augroup,
  callback = setup_highlights,
})

-- Call setup_highlights initially
setup_highlights()

-- LSP clients attached to buffer
local function lsp_clients()
  local current_buf = vim.api.nvim_get_current_buf()

  local clients = vim.lsp.get_clients { bufnr = current_buf }
  if next(clients) == nil then
    return ''
  end

  local c = {}
  for _, client in pairs(clients) do
    table.insert(c, client.name)
  end
  return ' 󰌘 ' .. table.concat(c, '|')
end
--- @return string
local function filename()
  local fname = vim.fn.expand('%:t')
  if fname == '' then
    return ''
  end
  return fname .. ' '
end

--- @param severity integer
--- @return integer
local function get_lsp_diagnostics_count(severity)
  if not rawget(vim, 'lsp') then
    return 0
  end

  local count = vim.diagnostic.count(0, { serverity = severity })[severity]
  if count == nil then
    return 0
  end

  return count
end

--- @param type string
--- @return integer
local function get_git_diff(type)
  local gsd = vim.b.gitsigns_status_dict
  if gsd and gsd[type] then
    return gsd[type]
  end

  return 0
end

local modes = {
  ['n'] = 'NORMAL',
  ['no'] = 'NORMAL',
  ['v'] = 'VISUAL',
  ['V'] = 'VISUAL LINE',
  [''] = 'VISUAL BLOCK',
  ['s'] = 'SELECT',
  ['S'] = 'SELECT LINE',
  [''] = 'SELECT BLOCK',
  ['i'] = 'INSERT',
  ['ic'] = 'INSERT',
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
local function lsp_active()
  if not rawget(vim, 'lsp') then
    return ''
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients { bufnr = current_buf }

  local space = '%#StatusLineMedium# %*'

  if #clients > 0 then
    return space .. '%#StatusLineLspActive# %*' .. space .. 'LSP'
  end

  return ''
end

--- @return string
local function diagnostics_error()
  local count = get_lsp_diagnostics_count(vim.diagnostic.severity.ERROR)
  if count > 0 then
    return string.format('%%#StatusLineLspError#  %s%%*', count)
  end

  return ''
end

--- @return string
local function diagnostics_warns()
  local count = get_lsp_diagnostics_count(vim.diagnostic.severity.WARN)
  if count > 0 then
    return string.format('%%#StatusLineLspWarn#  %s%%*', count)
  end

  return ''
end

--- @return string
local function diagnostics_hint()
  local count = get_lsp_diagnostics_count(vim.diagnostic.severity.HINT)
  if count > 0 then
    return string.format('%%#StatusLineLspHint#  %s%%*', count)
  end

  return ''
end

--- @return string
local function diagnostics_info()
  local count = get_lsp_diagnostics_count(vim.diagnostic.severity.INFO)
  if count > 0 then
    return string.format('%%#StatusLineLspInfo#  %s%%*', count)
  end

  return ''
end

--- @class LspProgress
--- @field client vim.lsp.Client?
--- @field kind string?
--- @field title string?
--- @field percentage integer?
--- @field message string?
local lsp_progress = {
  client = nil,
  kind = nil,
  title = nil,
  percentage = nil,
  message = nil,
}

vim.api.nvim_create_autocmd('LspProgress', {
  group = statusline_augroup,
  desc = 'Update LSP progress in statusline',
  pattern = { 'begin', 'report', 'end' },
  callback = function(args)
    if not (args.data and args.data.client_id) then
      return
    end

    lsp_progress = {
      client = vim.lsp.get_client_by_id(args.data.client_id),
      kind = args.data.params.value.kind,
      message = args.data.params.value.message,
      percentage = args.data.params.value.percentage,
      title = args.data.params.value.title,
    }

    if lsp_progress.kind == 'end' then
      lsp_progress.title = nil
      vim.defer_fn(function()
        vim.cmd.redrawstatus()
      end, 500)
    else
      vim.cmd.redrawstatus()
    end
  end,
})

--- @return string
local function lsp_status()
  if not rawget(vim, 'lsp') then
    return ''
  end

  if vim.o.columns < 120 then
    return ''
  end

  if not lsp_progress.client or not lsp_progress.title then
    return ''
  end

  local title = lsp_progress.title or ''
  local percentage = (lsp_progress.percentage and (lsp_progress.percentage .. '%%')) or ''
  local message = lsp_progress.message or ''

  local lsp_message = string.format('%s', title)

  if message ~= '' then
    lsp_message = string.format('%s %s', lsp_message, message)
  end

  if percentage ~= '' then
    lsp_message = string.format('%s %s', lsp_message, percentage)
  end

  return string.format('%%#StatusLineLspMessages#%s%%* ', lsp_message)
end

--- @return string
local function git_diff_added()
  local added = get_git_diff('added')
  if added > 0 then
    return string.format('%%#StatusLineGitDiffAdded#  %s%%*', added)
  end

  return ''
end

--- @return string
local function git_diff_changed()
  local changed = get_git_diff('changed')
  if changed > 0 then
    return string.format('%%#StatusLineGitDiffChanged#  %s%%*', changed)
  end

  return ''
end

--- @return string
local function git_diff_removed()
  local removed = get_git_diff('removed')
  if removed > 0 then
    return string.format('%%#StatusLineGitDiffRemoved#  %s%%*', removed)
  end

  return ''
end

--- @return string
local function git_branch_icon()
  return '%#StatusLineGitBranchIcon#%*'
end

--- @return string
local function git_branch()
  local branch = vim.b.gitsigns_head

  if branch == '' or branch == nil then
    return ''
  end

  return string.format('%%#StatusLineMedium#%s%%*', branch)
end

--- @return string
local function full_git()
  local full = ''
  local space = '%#StatusLineMedium# %*'

  local branch = git_branch()
  if branch ~= '' then
    local icon = git_branch_icon()
    full = full .. space .. icon .. space .. branch .. space
  end

  local added = git_diff_added()
  if added ~= '' then
    full = full .. added .. space
  end

  local changed = git_diff_changed()
  if changed ~= '' then
    full = full .. changed .. space
  end

  local removed = git_diff_removed()
  if removed ~= '' then
    full = full .. removed .. space
  end

  return full
end

--- @return string
local function file_percentage()
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_line_count(0)

  return string.format('%%#StatusLineMedium#  %d%%%% %%*', math.ceil(current_line / lines * 100))
end

--- @return string
local function total_lines()
  local lines = vim.fn.line('$')
  return string.format('%%#StatusLineMedium#of %s %%*', lines)
end

--- @param hlgroup string
local function formatted_filetype(hlgroup)
  local filetype = vim.bo.filetype or vim.fn.expand('%:e', false)
  return string.format('%%#%s# %s %%*', hlgroup, filetype)
end

local function filetype()
  local MiniIcons = require('mini.icons')
  local filetype = vim.bo.filetype

  local icon, icon_hl, _ = MiniIcons.get('filetype', filetype)

  return string.format('%%#%s#%s %%#StatuslineTitle#%s', icon_hl, icon, filetype)
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
    '▊',
    mode(),
    filename(),
    full_git(),
    '%=',
    '%S ',
    lsp_status(),
    lsp_active(),
    diagnostics_error(),
    diagnostics_warns(),
    diagnostics_hint(),
    diagnostics_info(),
    '%=',
    file_percentage(),
    total_lines(),
    filetype(),
    lsp_clients(),
    ' ▊',
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
