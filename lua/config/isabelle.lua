local M = {}

-- Defaults {{{
local hl_group_map = {
  ['background_unprocessed1'] = false,
  ['background_running1'] = false,
  ['background_canceled'] = false,
  ['background_bad'] = false,
  ['background_intensify'] = false,
  ['background_markdown_bullet1'] = 'markdownH1',
  ['background_markdown_bullet2'] = 'markdownH2',
  ['background_markdown_bullet3'] = 'markdownH3',
  ['background_markdown_bullet4'] = 'markdownH4',
  ['foreground_quoted'] = false,
  ['text_main'] = 'Normal',
  ['text_quasi_keyword'] = 'Keyword',
  ['text_free'] = 'Function',
  ['text_bound'] = 'Identifier',
  ['text_inner_numeral'] = false,
  ['text_inner_quoted'] = 'String',
  ['text_comment1'] = 'Comment',
  ['text_comment2'] = false,
  ['text_comment3'] = false,
  ['text_dynamic'] = false,
  ['text_class_parameter'] = false,
  ['text_antiquote'] = 'Comment',
  ['text_raw_text'] = 'Comment',
  ['text_plain_text'] = 'String',
  ['text_overview_unprocessed'] = false,
  ['text_overview_running'] = 'Bold',
  ['text_overview_error'] = false,
  ['text_overview_warning'] = false,
  ['dotted_writeln'] = false,
  ['dotted_warning'] = 'DiagnosticWarn',
  ['dotted_information'] = false,
  ['spell_checker'] = 'Underlined',
  ['text_inner_cartouche'] = false,
  ['text_var'] = 'Function',
  ['text_skolem'] = 'Identifier',
  ['text_tvar'] = 'Type',
  ['text_tfree'] = 'Type',
  ['text_operator'] = 'Function',
  ['text_improper'] = 'Keyword',
  ['text_keyword3'] = 'Keyword',
  ['text_keyword2'] = 'Keyword',
  ['text_keyword1'] = 'Keyword',
  ['foreground_antiquoted'] = false,
}

local defaults = {
  isabelle_path = vim.g.isabelle_path,
  vsplit = false,
  sh_path = 'sh', -- Windows: set to your sh-like shell
  unicode_symbols_output = false,
  unicode_symbols_edits = false,
  hl_group_map = hl_group_map,
  log = nil,
  verbose = false,
}
-- }}}

-- Utils {{{
local is_windows = vim.loop.os_uname().version:match('Windows')

local function normalize_path(p)
  local abs = vim.fn.fnamemodify(p, ':p')
  local ok, norm = pcall(vim.fs.normalize, abs)
  return ok and norm or abs
end

local function get_uri_from_fname(fname)
  return vim.uri_from_fname(normalize_path(fname))
end

local function find_buffer_by_uri(uri)
  for _, buf in ipairs(vim.fn.getbufinfo { bufloaded = 1 }) do
    local bufname = vim.fn.bufname(buf.bufnr)
    local fname = vim.fn.fnamemodify(bufname, ':p')
    local bufuri = get_uri_from_fname(fname)
    if bufuri == uri then
      return buf.bufnr
    end
  end
  return nil
end

local function send_request(client, method, payload, callback)
  client.request('PIDE/' .. method, payload, function(err, result)
    if err then
      error(tostring(err))
    end
    callback(result)
  end, 0)
end

local function send_notification(client, method, payload)
  send_request(client, method, payload, function(_) end)
end

local function send_notification_to_all(method, payload)
  local clients = vim.lsp.get_clients { name = 'isabelle' }
  for _, client in ipairs(clients) do
    send_notification(client, method, payload)
  end
end

local function caret_update(client)
  local bufnr = vim.api.nvim_get_current_buf()
  local fname = vim.api.nvim_buf_get_name(bufnr)
  local uri = get_uri_from_fname(fname)
  local win = vim.api.nvim_get_current_win()
  local line, col = unpack(vim.api.nvim_win_get_cursor(win))
  line = line - 1
  local line_s = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1]
  col = vim.fn.charidx(line_s .. ' ', col)
  send_notification(client, 'caret_update', { uri = uri, line = line, character = col })
end

local function get_min_width(bufnr)
  local windows = vim.fn.win_findbuf(bufnr)
  local min_width
  for _, window in ipairs(windows) do
    local width = vim.api.nvim_win_get_width(window)
    if not min_width or min_width < width then
      min_width = width
    end
  end
  return min_width
end

local function set_output_margin(client, size)
  if size then
    send_notification(client, 'output_set_margin', { margin = size - 8 })
  end
end

local function set_state_margin(client, id, size)
  if size then
    send_notification(client, 'state_set_margin', { id = id, margin = size - 8 })
  end
end

local function convert_symbols(client, bufnr, text)
  send_request(client, 'symbols_convert_request', { text = text, unicode = true }, function(t)
    local lines = {}
    for s in t.text:gmatch('([^\r\n]*)\n?') do
      table.insert(lines, s)
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end)
end

local function apply_decoration(bufnr, hl_group, syn_id, content)
  for _, range in ipairs(content) do
    local start_line = range.range[1]
    local start_col = range.range[2]
    local end_line = range.range[3]
    local end_col = range.range[4]
    local sline = vim.api.nvim_buf_get_lines(bufnr, start_line, start_line + 1, false)[1]
    start_col = vim.fn.byteidx(sline, start_col)
    local eline = vim.api.nvim_buf_get_lines(bufnr, end_line, end_line + 1, false)[1]
    end_col = vim.fn.byteidx(eline, end_col)
    pcall(vim.api.nvim_buf_set_extmark, bufnr, syn_id, start_line, start_col, {
      hl_group = hl_group,
      end_line = end_line,
      end_col = end_col,
    })
  end
end
-- }}}

local function apply_config(user_config)
  local config = setmetatable(user_config or {}, { __index = defaults })

  local hl_group_namespace_map = {}
  for group, _ in pairs(config.hl_group_map) do
    hl_group_namespace_map[group] = vim.api.nvim_create_namespace('isabelle-lsp.' .. group)
  end
  local output_namespace = vim.api.nvim_create_namespace('isabelle-lsp.dynamic_output')

  -- Build server command {{{
  local cmd
  if not is_windows then
    cmd = {
      config.isabelle_path,
      'vscode_server',
      '-o',
      'vscode_pide_extensions',
      '-o',
      'vscode_html_output=false',
      '-o',
      'editor_output_state',
    }
    if config.unicode_symbols_output then
      table.insert(cmd, '-o')
      table.insert(cmd, 'vscode_unicode_symbols_output')
    end
    if config.unicode_symbols_edits then
      table.insert(cmd, '-o')
      table.insert(cmd, 'vscode_unicode_symbols_edits')
    end
    if config.verbose then
      table.insert(cmd, '-v')
    end
    if config.log then
      table.insert(cmd, '-L')
      table.insert(cmd, config.log)
    end
  else
    local unicode_options_output = config.unicode_symbols_output and ' -o vscode_unicode_symbols_output' or ''
    local unicode_option_edits = config.unicode_symbols_edits and ' -o vscode_unicode_symbols_edits' or ''
    local verbose = config.verbose and ' -v' or ''
    local log = config.log and (' -L ' .. config.log) or ''
    cmd = {
      config.sh_path,
      '-c',
      'cd '
        .. vim.fn.fnamemodify(config.isabelle_path, ':h')
        .. ' && ./isabelle vscode_server -o vscode_pide_extensions -o vscode_html_output=false -o editor_output_state'
        .. unicode_options_output
        .. unicode_option_edits
        .. verbose
        .. log,
    }
  end
  -- }}}

  local output_buffer
  local state_buffers = {}

  local lsp_cfg = {
    name = 'isabelle',
    cmd = cmd,
    filetypes = { 'isabelle' },
    root_dir = function(bufnr, on_dir)
      local fname = vim.api.nvim_buf_get_name(bufnr)
      on_dir(vim.fn.fnamemodify(fname, ':h'))
    end,
    on_attach = function(client, bufnr)
      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        buffer = bufnr,
        callback = function(_)
          caret_update(client)
        end,
      })

      if not output_buffer then
        output_buffer = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_buf_set_name(output_buffer, '--OUTPUT--')
        vim.api.nvim_set_option_value('filetype', 'isabelle_output', { buf = output_buffer })
        vim.api.nvim_buf_set_lines(output_buffer, 0, -1, false, {})
        if config.vsplit then
          vim.api.nvim_command('vsplit')
          vim.api.nvim_command('wincmd l')
        else
          vim.api.nvim_command('split')
          vim.api.nvim_command('wincmd j')
        end
        vim.api.nvim_set_current_buf(output_buffer)
        vim.api.nvim_create_autocmd({ 'BufEnter' }, {
          buffer = output_buffer,
          callback = function(_)
            if #vim.api.nvim_list_wins() == 1 then
              vim.cmd('quit')
            end
          end,
        })
        if config.vsplit then
          vim.api.nvim_command('wincmd h')
        else
          vim.api.nvim_command('wincmd k')
        end
        set_output_margin(client, get_min_width(output_buffer))
      end

      vim.api.nvim_create_autocmd('WinResized', {
        callback = function(_)
          set_output_margin(client, get_min_width(output_buffer))
        end,
      })
    end,
    handlers = {
      ['PIDE/dynamic_output'] = function(_, params, _)
        if not output_buffer then
          return
        end
        local lines = {}
        for s in params.content:gmatch('([^\r\n]*)\n?') do
          table.insert(lines, s)
        end
        vim.api.nvim_buf_set_lines(output_buffer, 0, -1, false, lines)
        vim.api.nvim_buf_clear_namespace(output_buffer, output_namespace, 0, -1)
        for _, dec in ipairs(params.decorations) do
          local hl_group = config.hl_group_map[dec.type]
          if hl_group == nil then
            vim.notify('Could not find hl_group ' .. dec.type .. '.')
            goto continue
          end
          if hl_group == false then
            goto continue
          end
          apply_decoration(output_buffer, hl_group, output_namespace, dec.content)
          ::continue::
        end
      end,
      ['PIDE/decoration'] = function(_, params, _)
        local bufnr = find_buffer_by_uri(params.uri)
        if not bufnr then
          vim.notify('Could not find buffer for ' .. params.uri .. '.')
          return
        end
        for _, entry in ipairs(params.entries) do
          local syn_id = hl_group_namespace_map[entry.type]
          local hl_group = config.hl_group_map[entry.type]
          if not syn_id then
            vim.notify('Could not find hl_group ' .. entry.type .. '.')
            goto continue
          end
          if not hl_group then
            goto continue
          end
          vim.api.nvim_buf_clear_namespace(bufnr, syn_id, 0, -1)
          apply_decoration(bufnr, hl_group, syn_id, entry.content)
          ::continue::
        end
      end,
      ['PIDE/state_output'] = function(_, params, _)
        local id = params.id
        local buf = state_buffers[id]
        local lines = {}
        for s in params.content:gmatch('([^\r\n]*)\n?') do
          table.insert(lines, s)
        end
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.api.nvim_buf_clear_namespace(buf, output_namespace, 0, -1)
        for _, dec in ipairs(params.decorations) do
          local hl_group = config.hl_group_map[dec.type]
          if hl_group == nil then
            vim.notify('Could not find hl_group ' .. dec.type .. '.')
            goto continue
          end
          if hl_group == false then
            goto continue
          end
          apply_decoration(buf, hl_group, output_namespace, dec.content)
          ::continue::
        end
      end,
    },
  }

  vim.lsp.config('isabelle', lsp_cfg)
  if not vim.lsp.is_enabled('isabelle') then
    vim.lsp.enable('isabelle')
  end

  -- User commands
  pcall(vim.api.nvim_create_user_command, 'StateInit', function()
    local clients = vim.lsp.get_clients { name = 'isabelle' }
    for _, client in ipairs(clients) do
      send_request(client, 'state_init', {}, function(result)
        local id = result.state_id
        local new_buf = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_buf_set_name(new_buf, '--STATE-- ' .. id)
        vim.api.nvim_set_option_value('filetype', 'isabelle_output', { buf = new_buf })
        vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, {})
        vim.api.nvim_command('vsplit')
        vim.api.nvim_command('wincmd l')
        vim.api.nvim_set_current_buf(new_buf)
        vim.api.nvim_command('wincmd h')
        set_state_margin(client, id, get_min_width(new_buf))
        vim.api.nvim_create_autocmd('WinResized', {
          callback = function(_)
            set_state_margin(client, id, get_min_width(new_buf))
          end,
        })
        state_buffers[id] = new_buf
      end)
    end
  end, {})

  pcall(vim.api.nvim_create_user_command, 'SymbolsRequest', function()
    send_notification_to_all('symbols_request', {})
  end, {})

  pcall(vim.api.nvim_create_user_command, 'SymbolsConvert', function()
    local clients = vim.lsp.get_clients { name = 'isabelle' }
    local buf = vim.api.nvim_get_current_buf()
    local text = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local t = table.concat(text, '\n')
    for _, client in ipairs(clients) do
      convert_symbols(client, buf, t)
    end
  end, {})
end

function M.setup(user_config)
  apply_config(user_config)
||||||| a74dfa8
=======
-- vi: foldmethod=marker

-- Native vim.lsp starter for Isabelle — no lspconfig required.
-- This is a simplified variant of lua/isabelle-lsp.lua that can be
-- dropped into a config or required directly.

local M = {}

local is_windows = vim.loop.os_uname().version:match('Windows')

-- Default options kept minimal for a lightweight drop-in.
local default_config = {
  isabelle_path = 'isabelle',
  vsplit = false,
  sh_path = 'sh', -- only relevant for Windows
  unicode_symbols_output = false,
  unicode_symbols_edits = false,
  -- Optional decoration mapping. When empty, decorations are skipped.
  -- See lua/defaults.lua in the plugin for a comprehensive map.
  hl_group_map = {},
  log = nil,
  verbose = false,
  -- Register simple user commands (StateInit, SymbolsRequest, SymbolsConvert)
  create_commands = true,
}

local function merge_user_config(user)
  local cfg = {}
  for k, v in pairs(default_config) do
    cfg[k] = v
  end
  if type(user) == 'table' then
    for k, v in pairs(user) do
      cfg[k] = v
    end
  end
  return cfg
end

local function get_uri_from_fname(fname)
  local abs = vim.fn.fnamemodify(fname, ':p')
  return vim.uri_from_fname(abs)
end

local function find_buffer_by_uri(uri)
  for _, buf in ipairs(vim.fn.getbufinfo { bufloaded = 1 }) do
    local bufname = vim.fn.bufname(buf.bufnr)
    local fname = vim.fn.fnamemodify(bufname, ':p')
    local bufuri = get_uri_from_fname(fname)
    if bufuri == uri then
      return buf.bufnr
    end
  end
  return nil
end

local function send_request(client, method, payload, callback)
  client.request('PIDE/' .. method, payload, function(err, result)
    if err then
      error(tostring(err))
    end
    callback(result)
  end, 0)
end

local function send_notification(client, method, payload)
  send_request(client, method, payload, function(_) end)
end

local function caret_update(client)
  local bufnr = vim.api.nvim_get_current_buf()
  local fname = vim.api.nvim_buf_get_name(bufnr)
  local uri = get_uri_from_fname(fname)

  local win = vim.api.nvim_get_current_win()
  local line, col = unpack(vim.api.nvim_win_get_cursor(win))
  line = line - 1 -- make 0-indexed for server

  local line_s = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1]
  col = vim.fn.charidx((line_s or '') .. ' ', col)

  send_notification(client, 'caret_update', { uri = uri, line = line, character = col })
end

local function get_min_width(bufnr)
  local windows = vim.fn.win_findbuf(bufnr)
  local min_width
  for _, window in ipairs(windows) do
    local width = vim.api.nvim_win_get_width(window)
    if not min_width or min_width < width then
      min_width = width
    end
  end
  return min_width
end

local function apply_decoration(bufnr, hl_group, ns, content)
  for _, range in ipairs(content or {}) do
    local start_line = range.range[1]
    local start_col = range.range[2]
    local end_line = range.range[3]
    local end_col = range.range[4]

    local sline = vim.api.nvim_buf_get_lines(bufnr, start_line, start_line + 1, false)[1] or ''
    start_col = vim.fn.byteidx(sline, start_col)
    local eline = vim.api.nvim_buf_get_lines(bufnr, end_line, end_line + 1, false)[1] or ''
    end_col = vim.fn.byteidx(eline, end_col)

    pcall(
      vim.api.nvim_buf_set_extmark,
      bufnr,
      ns,
      start_line,
      start_col,
      { hl_group = hl_group, end_line = end_line, end_col = end_col }
    )
  end
end

local function build_cmd(config)
  if not is_windows then
    local cmd = {
      config.isabelle_path,
      'vscode_server',
      '-o',
      'vscode_pide_extensions',
      '-o',
      'vscode_html_output=false',
      '-o',
      'editor_output_state',
    }
    if config.unicode_symbols_output then
      table.insert(cmd, '-o')
      table.insert(cmd, 'vscode_unicode_symbols_output')
    end
    if config.unicode_symbols_edits then
      table.insert(cmd, '-o')
      table.insert(cmd, 'vscode_unicode_symbols_edits')
    end
    if config.verbose then
      table.insert(cmd, '-v')
    end
    if config.log then
      table.insert(cmd, '-L')
      table.insert(cmd, config.log)
    end
    return cmd
  end

  local unicode_options_output = config.unicode_symbols_output and ' -o vscode_unicode_symbols_output' or ''
  local unicode_option_edits = config.unicode_symbols_edits and ' -o vscode_unicode_symbols_edits' or ''
  local verbose = config.verbose and ' -v' or ''
  local log = config.log and (' -L ' .. config.log) or ''

  local isabelle_dir = vim.fs.dirname(config.isabelle_path)
  return {
    config.sh_path,
    '-c',
    'cd '
      .. isabelle_dir
      .. ' && ./isabelle vscode_server -o vscode_pide_extensions -o vscode_html_output=false -o editor_output_state'
      .. unicode_options_output
      .. unicode_option_edits
      .. verbose
      .. log,
  }
end

-- Per-client state
local client_state = {}

local function ensure_state(client_id, cfg)
  local st = client_state[client_id]
  if st then
    return st
  end
  st = {
    output_namespace = vim.api.nvim_create_namespace('isabelle-lsp.dynamic_output'),
    output_buffer = nil,
    state_buffers = {},
    hl_group_namespace_map = {},
    config = cfg,
  }
  for group, _ in pairs(cfg.hl_group_map or {}) do
    st.hl_group_namespace_map[group] = vim.api.nvim_create_namespace('isabelle-lsp.' .. group)
  end
  client_state[client_id] = st
  return st
end

local function set_output_margin(client, size)
  if size then
    send_notification(client, 'output_set_margin', { margin = size - 8 })
  end
end

local function set_state_margin(client, id, size)
  if size then
    send_notification(client, 'state_set_margin', { id = id, margin = size - 8 })
  end
end

local function make_handlers(cfg)
  return {
    ['PIDE/dynamic_output'] = function(_, params, ctx, _)
      local st = ensure_state(ctx.client_id, cfg)
      local buf = st.output_buffer
      if not buf then
        return
      end

      local lines = {}
      for s in (params.content or ''):gmatch('([^\r\n]*)\n?') do
        table.insert(lines, s)
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      vim.api.nvim_buf_clear_namespace(buf, st.output_namespace, 0, -1)
      for _, dec in ipairs(params.decorations or {}) do
        local hl_group = (cfg.hl_group_map or {})[dec.type]
        if hl_group == nil or hl_group == false then
          goto continue
        end
        apply_decoration(buf, hl_group, st.output_namespace, dec.content)
        ::continue::
      end
    end,

    ['PIDE/decoration'] = function(_, params, ctx, _)
      local st = ensure_state(ctx.client_id, cfg)
      local bufnr = find_buffer_by_uri(params.uri)
      if not bufnr then
        return
      end

      for _, entry in ipairs(params.entries or {}) do
        local ns = st.hl_group_namespace_map[entry.type]
        local hl_group = (cfg.hl_group_map or {})[entry.type]
        if not ns or not hl_group then
          goto continue
        end
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
        apply_decoration(bufnr, hl_group, ns, entry.content)
        ::continue::
      end
    end,

    ['PIDE/state_output'] = function(_, params, ctx, _)
      local st = ensure_state(ctx.client_id, cfg)
      local id = params.id
      local buf = st.state_buffers[id]
      if not buf then
        return
      end

      local lines = {}
      for s in (params.content or ''):gmatch('([^\r\n]*)\n?') do
        table.insert(lines, s)
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      vim.api.nvim_buf_clear_namespace(buf, st.output_namespace, 0, -1)
      for _, dec in ipairs(params.decorations or {}) do
        local hl_group = (cfg.hl_group_map or {})[dec.type]
        if hl_group == nil or hl_group == false then
          goto continue
        end
        apply_decoration(buf, hl_group, st.output_namespace, dec.content)
        ::continue::
      end
    end,
  }
end

local function on_attach_factory(cfg)
  return function(client, bufnr)
    local st = ensure_state(client.id, cfg)

    vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
      buffer = bufnr,
      callback = function(_)
        caret_update(client)
      end,
    })

    if not st.output_buffer then
      st.output_buffer = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_name(st.output_buffer, '--OUTPUT--')
      vim.api.nvim_set_option_value('filetype', 'isabelle_output', { buf = st.output_buffer })
      vim.api.nvim_buf_set_lines(st.output_buffer, 0, -1, false, {})

      if cfg.vsplit then
        vim.cmd('vsplit')
        vim.cmd('wincmd l')
      else
        vim.cmd('split')
        vim.cmd('wincmd j')
      end
      vim.api.nvim_set_current_buf(st.output_buffer)

      vim.api.nvim_create_autocmd({ 'BufEnter' }, {
        buffer = st.output_buffer,
        callback = function(_)
          if #vim.api.nvim_list_wins() == 1 then
            vim.cmd('quit')
          end
        end,
      })

      if cfg.vsplit then
        vim.cmd('wincmd h')
      else
        vim.cmd('wincmd k')
      end

      local min_width = get_min_width(st.output_buffer)
      set_output_margin(client, min_width)
    end

    vim.api.nvim_create_autocmd('WinResized', {
      callback = function(_)
        set_output_margin(client, get_min_width(st.output_buffer))
      end,
    })

    if cfg.create_commands then
      -- Register once per client
      if not st._commands_registered then
        st._commands_registered = true

        vim.api.nvim_create_user_command('StateInit', function()
          send_request(client, 'state_init', {}, function(result)
            local id = result.state_id
            local new_buf = vim.api.nvim_create_buf(true, true)
            vim.api.nvim_buf_set_name(new_buf, '--STATE-- ' .. id)
            vim.api.nvim_set_option_value('filetype', 'isabelle_output', { buf = new_buf })
            vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, {})

            vim.cmd('vsplit')
            vim.cmd('wincmd l')
            vim.api.nvim_set_current_buf(new_buf)
            vim.cmd('wincmd h')

            local min_width = get_min_width(new_buf)
            set_state_margin(client, id, min_width)
            vim.api.nvim_create_autocmd('WinResized', {
              callback = function(_)
                set_state_margin(client, id, get_min_width(new_buf))
              end,
            })

            st.state_buffers[id] = new_buf
          end)
        end, {})

        vim.api.nvim_create_user_command('SymbolsRequest', function()
          send_notification(client, 'symbols_request', {})
        end, {})

        vim.api.nvim_create_user_command('SymbolsConvert', function()
          local buf = vim.api.nvim_get_current_buf()
          local text = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          local t = table.concat(text, '\n')
          send_request(client, 'symbols_convert_request', { text = t, unicode = true }, function(resp)
            local lines = {}
            for s in (resp.text or ''):gmatch('([^\r\n]*)\n?') do
              table.insert(lines, s)
            end
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
          end)
        end, {})
      end
    end
  end
end

-- Public API

-- Make a vim.lsp.start config table without starting the client.
M.make_config = function(user_config)
  local cfg = merge_user_config(user_config)
  return {
    name = 'isabelle',
    cmd = build_cmd(cfg),
    root_dir = vim.fs.dirname(vim.api.nvim_buf_get_name(0)),
    on_attach = on_attach_factory(cfg),
    handlers = make_handlers(cfg),
    single_file_support = true,
  }
end

-- Start the Isabelle language server for the current buffer.
M.start = function(user_config)
  local config = M.make_config(user_config)
  return vim.lsp.start(config)
end

return M
