-- Acquisition-only observers. User actions are dispatched by the RPC client, not
-- by calling private plugin handlers or manufacturing autocmds.
local M = {}
local api, fn = vim.api, vim.fn
local S
local channel

local function buffer_text()
  return table.concat(api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    .. (vim.bo.endofline and "\n" or "")
end

local function disk_text(relative)
  local file = io.open(S.cfg.root .. "/" .. relative, "rb")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  return text
end

local function mapping(lhs, mode)
  local map = fn.maparg(lhs, mode or "n", false, true)
  return {
    present = next(map) ~= nil,
    buffer = map.buffer == 1,
    callback = type(map.callback) == "function",
    rhs = map.rhs,
    desc = map.desc,
  }
end

local function base_ready()
  return vim.v.vim_did_enter == 1
    and package.loaded["ui.statusline"] ~= nil
    and vim.o.statusline:find("ui.statusline", 1, true) ~= nil
    and type(_G.MiniCompletion) == "table"
    and package.loaded.pins ~= nil
    and mapping(" 1").present
    and mapping(" h").present
end

local function ready_file(relative, default_folds)
  local expected = S.file_facts[relative]
  local buf = api.nvim_get_current_buf()
  local path = api.nvim_buf_get_name(buf)
  local highlighter = vim.treesitter.highlighter.active[buf] ~= nil
  local evidence = {
    path = path,
    filetype = vim.bo.filetype,
    line_count = api.nvim_buf_line_count(buf),
    first_line = api.nvim_buf_get_lines(buf, 0, 1, false)[1],
    last_line = api.nvim_buf_get_lines(buf, -2, -1, false)[1],
    highlighter_active = highlighter,
    foldenable = vim.wo.foldenable,
    foldmethod = vim.wo.foldmethod,
    foldlevel = vim.wo.foldlevel,
    foldclosed = fn.foldclosed(S.cfg.lua_first_function),
    foldclosedend = fn.foldclosedend(S.cfg.lua_first_function),
  }
  local ok = path == S.cfg.root .. "/" .. relative
    and evidence.line_count == expected.count
    and evidence.first_line == expected.first
    and evidence.last_line == expected.last
  if expected.filetype and expected.filetype ~= "" then
    ok = ok and evidence.filetype == expected.filetype
  end
  if expected.syntax then
    ok = ok and highlighter
  end
  if default_folds then
    ok = ok
      and vim.wo.foldenable
      and vim.wo.foldmethod == "expr"
      and vim.wo.foldlevel == 0
      and evidence.foldclosed == S.cfg.lua_first_function
    local expected_end = relative == "lua/representative.lua"
        and S.cfg.lua_first_fold_end
      or S.cfg.rust_first_fold_end
    evidence.expected_fold_end = expected_end
    ok = ok and evidence.foldclosedend == expected_end
  end
  return ok, evidence
end

local function marks(namespace)
  local ns = api.nvim_get_namespaces()[namespace]
  if not ns then
    return {}
  end
  return api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
end

local function gutter(row)
  local found = false
  local values = marks("git-gutter")
  for _, mark in ipairs(values) do
    if mark[2] == row and mark[4].sign_hl_group == "GitGutterChange" then
      found = true
    end
  end
  return found,
    { namespace = "git-gutter", expected_row_zero_based = row, marks = values }
end

local function blame(row)
  local values = marks("git_blame")
  local found = false
  for _, mark in ipairs(values) do
    local text = ""
    for _, chunk in ipairs(mark[4].virt_text or {}) do
      text = text .. chunk[1]
    end
    if
      mark[2] == row
      and text:find(S.cfg.author, 1, true)
      and text:find(S.cfg.commit:sub(1, 8), 1, true)
    then
      found = true
    end
  end
  return found,
    {
      namespace = "git_blame",
      expected_row_zero_based = row,
      author = S.cfg.author,
      commit = S.cfg.commit,
      marks = values,
      configured_debounce_ms = 150,
    }
end

local function lsp_ready()
  local evidence =
    { clients = {}, omnifunc = vim.bo.omnifunc, gd_mapping = mapping("gd") }
  local found = false
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    local capabilities = client.server_capabilities or {}
    evidence.clients[#evidence.clients + 1] = {
      id = client.id,
      name = client.name,
      initialized = client.initialized == true,
      root_dir = client.config.root_dir,
      cmd = client.config.cmd,
      definition = capabilities.definitionProvider ~= nil
        and capabilities.definitionProvider ~= false,
      completion = capabilities.completionProvider ~= nil
        and capabilities.completionProvider ~= false,
    }
    if
      client.name == "lua-language-server"
      and client.initialized
      and capabilities.definitionProvider
      and capabilities.completionProvider
    then
      found = true
    end
  end
  return found
    and evidence.omnifunc == "v:lua.MiniCompletion.completefunc_lsp"
    and evidence.gd_mapping.present
    and evidence.gd_mapping.buffer
    and evidence.gd_mapping.callback,
    evidence
end

local function workspace_ready(clients)
  S.definition_barriers = S.definition_barriers or {}
  local evidence = {
    method = "textDocument/definition",
    expected_path = S.cfg.root .. "/lua/benchlib.lua",
    expected_row = S.cfg.lsp_definition_row - 1,
    expected_col = S.cfg.lsp_definition_col,
    clients = {},
  }
  local found, ready = false, true
  for _, details in ipairs(clients.clients) do
    if details.name == "lua-language-server" and details.initialized then
      found = true
      local state = S.definition_barriers[details.id]
      if not state then
        state = { client_id = details.id, ready = false }
        S.definition_barriers[details.id] = state
        local client = assert(vim.lsp.get_client_by_id(details.id))
        -- LuaLS waits for workspace readiness before answering definitions.
        -- A checked real result also works when loading is too quick to emit
        -- the optional progress UI. This request never changes the buffer.
        local accepted, request_id = client:request("textDocument/definition", {
          textDocument = {
            uri = vim.uri_from_fname(S.cfg.root .. "/lua/lsp_main.lua"),
          },
          position = { line = 2, character = S.cfg.lsp_use_col },
        }, function(err, result)
          state.completed_at_uv_hrtime_ns = vim.uv.hrtime()
          state.error = err and vim.inspect(err) or nil
          state.locations = result
          if not err and type(result) == "table" then
            local locations = result.uri and { result } or result
            for _, location in ipairs(locations) do
              local uri = location.targetUri or location.uri
              local range = location.targetSelectionRange or location.range
              if
                uri
                and range
                and vim.uri_to_fname(uri) == evidence.expected_path
                and range.start.line == evidence.expected_row
                and range.start.character == evidence.expected_col
              then
                state.ready = true
              end
            end
          end
          if not state.ready and not state.error then
            state.error =
              "definition did not resolve the expected project symbol"
          end
        end, api.nvim_get_current_buf())
        state.request_id = request_id
        if not accepted then
          state.error = "Lua server rejected the workspace readiness request"
        end
      end
      assert(not state.error, state.error)
      ready = ready and state.ready
      evidence.clients[#evidence.clients + 1] = state
    end
  end
  evidence.ready = found and ready
  return evidence.ready, evidence
end

local function pin_paths()
  local file = fn.stdpath("state")
    .. "/pins/"
    .. fn.sha256(S.cfg.root)
    .. ".json"
  local text =
    table.concat(fn.filereadable(file) == 1 and fn.readfile(file) or {}, "\n")
  local ok, paths = pcall(vim.json.decode, text)
  return ok and paths or {}, file
end

local function picker_ready(grep, unqueried)
  local pick = package.loaded["mini.pick"]
  if not pick then
    return false, { loaded = false }
  end
  local state = pick.get_picker_state()
  if not state then
    return false, { loaded = true, active = false }
  end
  local items = pick.get_picker_items() or {}
  local matches = pick.get_picker_matches() or {}
  local opts = pick.get_picker_opts() or {}
  local query = table.concat(pick.get_picker_query() or {})
  local source = opts.source or {}
  local source_name = source.name or ""
  local backend = source_name:match("%((%w+)") or "unknown"
  local current = matches.current
  local current_text = type(current) == "string" and current
    or (type(current) == "table" and (current.text or current.path) or "")
  local expected_query = unqueried and ""
    or (grep and S.cfg.grep_query or S.cfg.picker_query)
  local evidence = {
    loaded = true,
    active = true,
    busy = state.is_busy,
    source_name = source_name,
    backend = backend,
    backend_exepath = backend ~= "fallback" and fn.exepath(backend) or nil,
    item_count = #items,
    match_count = #(matches.all or {}),
    current = current,
    query = query,
    expected_query = expected_query,
  }
  if state.is_busy or query ~= expected_query then
    return false, evidence
  end
  if grep then
    local prefix = S.cfg.grep_target .. "\0" .. S.cfg.grep_line .. "\0"
    local valid = #items == 1
      and #((matches or {}).all or {}) == 1
      and current_text:find(prefix, 1, true) ~= nil
      and current_text:find(S.cfg.grep_query, 1, true) ~= nil
      and (backend == "rg" or backend == "git")
      and fn.executable(backend) == 1
    return valid, evidence
  end
  local expected_names = (backend == "git") and S.all_names or S.visible_names
  local actual = {}
  for _, item in ipairs(items) do
    if type(item) == "string" then
      actual[item:gsub("^%./", "")] = true
    end
  end
  local complete = true
  for _, name in ipairs(expected_names) do
    if not actual[name] then
      complete = false
      break
    end
  end
  if backend ~= "fallback" then
    complete = complete and #items == #expected_names
  end
  evidence.expected_item_count = #expected_names
  evidence.full_source_checked = complete
  return complete
    and (
      unqueried
      or (
        #(matches.all or {}) == 1
        and current_text:gsub("^%./", "") == S.cfg.picker_target
      )
    ),
    evidence
end

local function completion(lsp)
  local info = fn.complete_info({ "mode", "pum_visible", "items", "selected" })
  local target = lsp and S.cfg.lsp_completion_word or S.cfg.completion_word
  local found = false
  local evidence = {
    mode = info.mode,
    pum_visible = info.pum_visible,
    selected = info.selected,
    items = {},
    target = target,
    editor_mode = api.nvim_get_mode().mode,
  }
  for _, item in ipairs(info.items or {}) do
    local data = item.user_data
    local lsp_item = type(data) == "table"
        and type(data.lsp) == "table"
        and data.lsp.item
      or nil
    evidence.items[#evidence.items + 1] = {
      word = item.word,
      abbr = item.abbr,
      kind = item.kind,
      lsp_client_id = lsp_item and lsp_item.client_id or nil,
      lsp_label = lsp_item and lsp_item.label or nil,
    }
    local label = item.abbr or item.word or ""
    if
      label:find(target, 1, true) or (item.word or ""):find(target, 1, true)
    then
      if not lsp or (lsp_item and type(lsp_item.client_id) == "number") then
        found = true
      end
    end
  end
  local configured = _G.MiniCompletion ~= nil
    and package.loaded["mini.completion"] ~= nil
  if lsp then
    configured = configured
      and MiniCompletion.config.lsp_completion.source_func == "omnifunc"
  end
  evidence.configured_delay_ms = _G.MiniCompletion
      and MiniCompletion.config.delay.completion
    or nil
  if lsp then
    local ready, clients = lsp_ready()
    evidence.lsp = clients
    return found
      and configured
      and ready
      and info.pum_visible == 1
      and info.mode == "omni",
      evidence
  end
  return found
    and configured
    and info.pum_visible == 1
    and evidence.editor_mode:sub(1, 1) == "i",
    evidence
end

function M.check(oracle)
  if oracle == "control" then
    return true,
      { diagnostic = "inclusive RPC/oracle/redraw floor; never subtracted" }
  end
  if oracle == "prepared" then
    local ok, evidence = ready_file(S.prepared_file)
    if S.needs_lsp then
      local ready, clients = lsp_ready()
      evidence.lsp = clients
      ok = ok and ready
      if S.name == "completion-lsp-indexed" then
        local indexed, barrier = workspace_ready(clients)
        evidence.workspace_barrier = barrier
        ok = ok and indexed
      end
    end
    if S.name == "lint-lua" then
      local lint = package.loaded.lint
      evidence.running_linters = lint and lint.get_running(0)
        or { "not-loaded" }
      ok = ok and lint ~= nil and #evidence.running_linters == 0
      for _, diagnostic in ipairs(vim.diagnostic.get(0)) do
        if diagnostic.message:find(S.cfg.lint_token, 1, true) then
          ok = false
        end
      end
    end
    return ok, evidence
  end
  if oracle == "insert-prepared" then
    return api.nvim_get_mode().mode:sub(1, 1) == "i",
      { mode = api.nvim_get_mode().mode }
  end
  if oracle == "picker-prime" then
    return picker_ready(false, true)
  end
  if oracle == "picker-closed" then
    local pick = package.loaded["mini.pick"]
    local closed = pick and pick.get_picker_state() == nil
    return closed, { closed = closed, loaded = pick ~= nil }
  end
  if oracle == "gutter-dirty" then
    return gutter(1)
  end
  if oracle == "gutter-reset" then
    local values = marks("git-gutter")
    return #values == 0 and buffer_text() == S.cfg.original_text,
      { marks = values, text = buffer_text(), attachment_proven = true }
  end
  if oracle == "blame-prime" then
    return blame(0)
  end
  if oracle == "pins-off" or oracle == "pins-on" then
    local paths, file = pin_paths()
    local pinned = #paths == 1
      and paths[1] == S.cfg.root .. "/lua/representative.lua"
    return (oracle == "pins-on" and pinned)
      or (oracle == "pins-off" and #paths == 0),
      { paths = paths, state_file = file }
  end
  if oracle == "pins-away" then
    return ready_file("python/representative.py")
  end
  if oracle == "paste-inserted" then
    local text = buffer_text()
    local exact = text == S.cfg.pasted_text
    return exact,
      {
        inserted_exact = exact,
        expected_sha256 = S.cfg.pasted_sha256,
        line_count = api.nvim_buf_line_count(0),
        mode = api.nvim_get_mode().mode,
      }
  end
  local name = S.name
  if name:sub(1, 5) == "open-" then
    return ready_file(S.destination, name == "open-rust")
  end
  if name == "edit-insert" then
    local text = buffer_text()
    local mode = api.nvim_get_mode().mode
    local pairs_active = package.loaded["mini.pairs"] ~= nil
      and mapping("(", "i").present
    return text == "seed (alpha)[beta]{gamma}\n"
      and mode == "n"
      and pairs_active,
      {
        text = text,
        mode = mode,
        mini_pairs_active = pairs_active,
        pair_mapping = mapping("(", "i"),
      }
  end
  if name == "edit-paste-undo" then
    local text = buffer_text()
    local highlighter = vim.treesitter.highlighter.active[api.nvim_get_current_buf()]
      ~= nil
    local exact = text == S.cfg.original_text
    return exact
      and api.nvim_get_mode().mode == "n"
      and highlighter
      and vim.wo.foldmethod == "expr",
      {
        restored_exact = exact,
        expected_sha256 = S.cfg.original_sha256,
        line_count = api.nvim_buf_line_count(0),
        mode = api.nvim_get_mode().mode,
        inserted_lines = 96,
        highlighter_active = highlighter,
        foldmethod = vim.wo.foldmethod,
      }
  end
  if name == "treesitter-motion" then
    local cursor = api.nvim_win_get_cursor(0)
    local highlighter = vim.treesitter.highlighter.active[api.nvim_get_current_buf()]
      ~= nil
    return cursor[1] == S.cfg.lua_second_function
      and cursor[2] == 0
      and highlighter
      and mapping("]m").callback,
      {
        cursor = cursor,
        expected_cursor = { S.cfg.lua_second_function, 0 },
        highlighter_active = highlighter,
        mapping = mapping("]m"),
      }
  end
  if name == "folds" then
    local first, last =
      fn.foldclosed(S.cfg.lua_first_function),
      fn.foldclosedend(S.cfg.lua_first_function)
    local text = fn.foldtextresult(S.cfg.lua_first_function)
    local flattened = type(text) == "string" and text or ""
    if type(text) == "table" then
      for _, chunk in ipairs(text) do
        flattened = flattened .. chunk[1]
      end
    end
    local configured_text, configured_expr = vim.wo.foldtext, vim.wo.foldexpr
    local text_type = type(configured_text)
    local function describe(value)
      local result = { type = type(value) }
      if result.type == "function" then
        local info = debug.getinfo(value, "Sn")
        result.name, result.source, result.linedefined =
          info.name, info.source, info.linedefined
      elseif result.type == "string" then
        result.value = value
      end
      return result
    end
    local configured = text_type == "function"
      or (text_type == "string" and configured_text:find("lua", 1, true) ~= nil)
    local ok = first == S.cfg.lua_first_function
      and last == S.cfg.lua_first_fold_end
      and vim.wo.foldmethod == "expr"
      and configured
      and flattened:find("… 7 lines …", 1, true) ~= nil
    return ok,
      {
        foldclosed = first,
        foldclosedend = last,
        foldtext = text,
        flattened_foldtext = flattened,
        foldexpr = describe(configured_expr),
        configured_foldtext = describe(configured_text),
      }
  end
  if name == "scroll" then
    local cursor, view = api.nvim_win_get_cursor(0), fn.winsaveview()
    return cursor[1] == S.scroll_row
      and view.topline == S.scroll_row
      and cursor[2] == 0,
      {
        cursor = cursor,
        topline = view.topline,
        expected_row = S.scroll_row,
        half_page_lines = S.scroll,
        motion_count = 4,
      }
  end
  if name == "buffer-switch" or name == "pins-select" then
    local ok, evidence = ready_file("lua/representative.lua")
    evidence.statusline_configured = vim.o.statusline:find(
      "ui.statusline",
      1,
      true
    ) ~= nil
    evidence.gutter_namespace_present = api.nvim_get_namespaces()["git-gutter"]
      ~= nil
    if name == "pins-select" then
      evidence.pins, evidence.pin_state_file = pin_paths()
    end
    return ok
      and evidence.statusline_configured
      and evidence.gutter_namespace_present,
      evidence
  end
  if name == "split-resize" then
    local left, right = S.left, S.right
    local evidence = {
      current_window = api.nvim_get_current_win(),
      expected_window = right,
      left_width = api.nvim_win_get_width(left),
      right_width = api.nvim_win_get_width(right),
      left_position = api.nvim_win_get_position(left),
      right_position = api.nvim_win_get_position(right),
      expected_left_width = S.left_width + 6,
      expected_right_width = S.right_width - 6,
      resize_mapping = mapping("<M-l>"),
      move_mapping = mapping("<C-l>"),
    }
    return evidence.current_window == right
      and evidence.left_width == S.left_width + 6
      and evidence.right_width == S.right_width - 6
      and evidence.left_position[2] == 0
      and evidence.right_position[2] == S.left_width + 7
      and evidence.resize_mapping.callback
      and evidence.move_mapping.callback,
      evidence
  end
  if name == "completion-buffer" then
    return completion(false)
  end
  if name == "completion-lsp-indexed" then
    return completion(true)
  end
  if name == "picker-files-first" or name == "picker-files-repeat" then
    return picker_ready(false, false)
  end
  if name == "picker-grep" then
    return picker_ready(true, false)
  end
  if name == "git-gutter" then
    local ok, evidence = gutter(1)
    evidence.line = api.nvim_buf_get_lines(0, 1, 2, false)[1]
    return ok and evidence.line == "gutter baseline beta measured", evidence
  end
  if name == "git-blame" then
    return blame(1)
  end
  if name == "format-save-lua" then
    local text, disk = buffer_text(), disk_text("lua/format.lua")
    return text == S.cfg.format_expected
      and disk == S.cfg.format_expected
      and not vim.bo.modified,
      {
        text = text,
        disk_text = disk,
        expected = S.cfg.format_expected,
        modified = vim.bo.modified,
        formatter_exepath = fn.exepath("stylua"),
      }
  end
  if name == "lint-lua" then
    local expected = "local value = 1\n"
      .. S.cfg.lint_token
      .. "()\nlocal result = value + 2\nreturn result\n"
    local text, disk = buffer_text(), disk_text("lua/lint.lua")
    local found, matches = false, {}
    local lint = package.loaded.lint
    local expected_namespace = lint and lint.get_namespace("selene")
    for ns, details in pairs(vim.diagnostic.get_namespaces()) do
      for _, diagnostic in ipairs(vim.diagnostic.get(0, { namespace = ns })) do
        if
          ns == expected_namespace
          and diagnostic.source == "selene"
          and diagnostic.code == "undefined_variable"
          and diagnostic.message:find(S.cfg.lint_token, 1, true)
          and diagnostic.lnum == 1
        then
          found = true
          matches[#matches + 1] = {
            namespace = ns,
            namespace_name = details.name,
            source = diagnostic.source,
            code = diagnostic.code,
            lnum = diagnostic.lnum,
            col = diagnostic.col,
            message = diagnostic.message,
          }
        end
      end
    end
    return found
      and text == expected
      and disk == expected
      and not vim.bo.modified,
      {
        diagnostics = matches,
        expected_namespace = expected_namespace,
        text = text,
        disk_text = disk,
        expected = expected,
        modified = vim.bo.modified,
        linter_exepath = fn.exepath("selene"),
        formatter_exepath = fn.exepath("stylua"),
      }
  end
  if name == "lsp-lua-ready" then
    local file_ok, file = ready_file("lua/lsp_main.lua")
    local ok, evidence = lsp_ready()
    evidence.file = file
    return ok and file_ok, evidence
  end
  if name == "lsp-definition" then
    local path, cursor = api.nvim_buf_get_name(0), api.nvim_win_get_cursor(0)
    local ok, evidence = lsp_ready()
    evidence.path, evidence.cursor = path, cursor
    evidence.expected_path = S.cfg.root .. "/lua/benchlib.lua"
    evidence.expected_cursor =
      { S.cfg.lsp_definition_row, S.cfg.lsp_definition_col }
    evidence.source_mapping = S.definition_mapping
    return ok
      and S.definition_mapping.buffer
      and S.definition_mapping.callback
      and path == evidence.expected_path
      and cursor[1] == S.cfg.lsp_definition_row
      and cursor[2] == S.cfg.lsp_definition_col,
      evidence
  end
  error("unknown oracle: " .. tostring(oracle) .. "/" .. name)
end

function M.observe(token, oracle, timeout_ms)
  local deadline = vim.uv.hrtime() + timeout_ms * 1000000
  local last = { token = token, oracle = oracle, poll_cadence_ms = 1 }
  M.last_oracle = last
  local function poll()
    local ok, ready, evidence = pcall(M.check, oracle)
    last.checked_at_uv_hrtime_ns = vim.uv.hrtime()
    last.success = ok and ready == true
    last.evidence = ok and evidence or nil
    last.error = not ok and tostring(ready) or nil
    last.status = not ok and "error" or (ready and "ok" or "waiting")
    if not ok then
      vim.rpcnotify(
        channel,
        "poincare_benchmark",
        token,
        "error",
        { error = tostring(ready), oracle = oracle }
      )
      vim.cmd("redraw!")
      return
    end
    if ready or vim.uv.hrtime() >= deadline then
      last.status = ready and "ok" or "timeout"
      evidence.oracle = oracle
      evidence.success = ready == true
      evidence.poll_cadence_ms = 1
      vim.rpcnotify(
        channel,
        "poincare_benchmark",
        token,
        ready and "ok" or "timeout",
        evidence
      )
      -- The client accepts only a flush received AFTER this notification.
      vim.cmd("redraw!")
      return
    end
    vim.defer_fn(poll, 1)
  end
  poll()
end

function M.prepare(name, cfg, rpc_channel)
  channel = rpc_channel
  assert(
    base_ready(),
    "configured statusline/completion/pins were not initialized"
  )
  S = {
    name = name,
    cfg = cfg,
    file_facts = cfg.file_facts,
    all_names = cfg.all_names,
    visible_names = cfg.visible_names,
  }
  local required = ({
    ["format-save-lua"] = "stylua",
    ["lint-lua"] = "selene",
    ["lsp-lua-ready"] = "lua-language-server",
    ["lsp-definition"] = "lua-language-server",
    ["completion-lsp-indexed"] = "lua-language-server",
    ["git-gutter"] = "git",
    ["git-blame"] = "git",
  })[name]
  if required then
    assert(
      fn.executable(required) == 1,
      "required configured executable unavailable: " .. required
    )
  end
  if name == "picker-grep" then
    assert(
      fn.executable("rg") == 1 or fn.executable("git") == 1,
      "grep_live requires actual rg or git"
    )
  end
  local plan = { steps = {}, action = { kind = "input" }, oracle = "result" }
  local function open(relative)
    vim.cmd.edit(fn.fnameescape(cfg.root .. "/" .. relative))
    S.prepared_file = relative
    plan.steps[#plan.steps + 1] = { kind = "observe", oracle = "prepared" }
  end
  local destinations = {
    ["open-python"] = "python/representative.py",
    ["open-rust"] = "rust/representative.rs",
    ["open-nix"] = "nix/representative.nix",
    ["open-large"] = "python/large.py",
    ["lsp-lua-ready"] = "lua/lsp_main.lua",
  }
  if destinations[name] then
    S.destination = destinations[name]
    plan.action.input = ":edit "
      .. fn.fnameescape(cfg.root .. "/" .. S.destination)
      .. "<CR>"
  elseif name == "edit-insert" then
    open("text/edit.txt")
    plan.action.input = "A (alpha<Right>[beta<Right>{gamma<Esc>"
  elseif name == "edit-paste-undo" then
    open("lua/representative.lua")
    api.nvim_win_set_cursor(0, { 1, 0 })
    plan.steps[#plan.steps + 1] =
      { kind = "input", input = "i", oracle = "insert-prepared" }
    plan.action = { kind = "paste-undo", text = cfg.paste }
  elseif name == "treesitter-motion" or name == "folds" then
    open("lua/representative.lua")
    assert(mapping("]m").callback, "configured treesitter ]m mapping absent")
    vim.cmd("normal! zR")
    api.nvim_win_set_cursor(0, { cfg.lua_first_function, 0 })
    plan.action.input = name == "folds" and "zM" or "]m"
  elseif name == "scroll" then
    open("python/representative.py")
    vim.cmd("normal! ggzt")
    S.scroll = vim.wo.scroll
    assert(
      S.scroll > 0 and vim.wo.scrolloff == 0,
      "scroll workload requires configured default half-page/scrolloff behavior"
    )
    S.scroll_row = 1 + 2 * S.scroll
    plan.action.input = "<C-d><C-d><C-d><C-u>"
  elseif name == "buffer-switch" then
    open("lua/representative.lua")
    open("python/representative.py")
    -- All preparation observers run after prepare(), so only the current file
    -- is checked here; both actual :edit operations above retain normal hooks.
    table.remove(plan.steps, 1)
    plan.action.input = "<C-^>"
  elseif name == "split-resize" then
    open("lua/representative.lua")
    vim.cmd("vsplit")
    vim.cmd("wincmd h")
    S.left = api.nvim_get_current_win()
    vim.cmd("wincmd l")
    S.right = api.nvim_get_current_win()
    S.left_width, S.right_width =
      api.nvim_win_get_width(S.left), api.nvim_win_get_width(S.right)
    vim.cmd("wincmd h")
    plan.action.input = "2<M-l><C-l>"
  elseif name == "completion-buffer" then
    open("text/completion.txt")
    api.nvim_win_set_cursor(0, { 3, 0 })
    plan.action.input = "ibenchmark_al"
  elseif
    name == "picker-files-first"
    or name == "picker-files-repeat"
    or name == "picker-grep"
  then
    if name == "picker-files-first" then
      assert(
        package.loaded["mini.pick"] == nil,
        "first-use picker was already loaded"
      )
    end
    assert(
      mapping(name == "picker-grep" and " /" or " f").present,
      "configured picker mapping absent"
    )
    if name == "picker-files-repeat" then
      plan.steps[#plan.steps + 1] =
        { kind = "input", input = " f", oracle = "picker-prime" }
      plan.steps[#plan.steps + 1] =
        { kind = "input", input = "<Esc>", oracle = "picker-closed" }
    end
    plan.action.input = name == "picker-grep" and (" /" .. cfg.grep_query)
      or (" f" .. cfg.picker_query)
  elseif name == "git-gutter" then
    open("text/gutter.txt")
    api.nvim_win_set_cursor(0, { 2, 0 })
    plan.steps[#plan.steps + 1] =
      { kind = "input", input = "A prepared<Esc>", oracle = "gutter-dirty" }
    plan.steps[#plan.steps + 1] =
      { kind = "input", input = "u", oracle = "gutter-reset" }
    plan.action.input = "A measured<Esc>"
  elseif name == "git-blame" then
    open("text/gutter.txt")
    assert(fn.exists(":GitBlame") == 2, "configured GitBlame command absent")
    api.nvim_win_set_cursor(0, { 1, 0 })
    plan.steps[#plan.steps + 1] = { kind = "observe", oracle = "blame-prime" }
    plan.action.input = "j"
  elseif name == "pins-select" then
    open("lua/representative.lua")
    local paths = pin_paths()
    if #paths > 0 then
      assert(
        #paths == 1 and paths[1] == cfg.root .. "/lua/representative.lua",
        "unexpected isolated fixture pin state"
      )
      plan.steps[#plan.steps + 1] =
        { kind = "input", input = " h", oracle = "pins-off" }
    end
    plan.steps[#plan.steps + 1] =
      { kind = "input", input = " h", oracle = "pins-on" }
    plan.steps[#plan.steps + 1] = {
      kind = "input",
      input = ":edit " .. fn.fnameescape(
        cfg.root .. "/python/representative.py"
      ) .. "<CR>",
      oracle = "pins-away",
    }
    plan.action.input = " 1"
  elseif name == "format-save-lua" then
    open("lua/format.lua")
    plan.action.input = ":write<CR>"
  elseif name == "lint-lua" then
    open("lua/lint.lua")
    api.nvim_win_set_cursor(0, { 2, 0 })
    plan.action.input = "O" .. cfg.lint_token .. "()<Esc>:write<CR>"
  elseif name == "lsp-definition" or name == "completion-lsp-indexed" then
    open("lua/lsp_main.lua")
    S.needs_lsp = true
    if name == "lsp-definition" then
      api.nvim_win_set_cursor(0, { 3, cfg.lsp_use_col })
      -- Captured after attach by finalize(), before the timed action.
      plan.action.input = "gd"
    else
      assert(
        not buffer_text():find(cfg.lsp_completion_word, 1, true),
        "LSP candidate must not be in the source buffer"
      )
      api.nvim_win_set_cursor(0, { 4, 0 })
      plan.action.input = "Olocal completed = library.benchmark_comp<C-x><C-o>"
    end
  elseif name == "redraw-control" then
    plan.action = { kind = "control" }
    plan.oracle = "control"
  else
    error("unimplemented workload: " .. name)
  end
  return plan
end

function M.finalize()
  if S.name == "lsp-definition" then
    S.definition_mapping = mapping("gd")
    assert(
      S.definition_mapping.buffer and S.definition_mapping.callback,
      "configured LSP gd buffer mapping absent"
    )
  end
  local facts = {
    configured = base_ready(),
    first_use_picker = S.name == "picker-files-first"
        and package.loaded["mini.pick"] == nil
      or nil,
  }
  if S.name == "completion-lsp-indexed" then
    local attached, clients = lsp_ready()
    local indexed, barrier = workspace_ready(clients)
    assert(
      attached and indexed,
      "configured Lua definition readiness changed before completion input"
    )
    facts.workspace_barrier = barrier
  end
  return facts
end

function M.runtime()
  local tools = {}
  for _, name in ipairs({
    "git",
    "rg",
    "fd",
    "stylua",
    "selene",
    "lua-language-server",
    "rust-analyzer",
    "rustfmt",
    "cargo",
    "nil",
    "nixd",
    "alejandra",
    "nixfmt",
    "statix",
    "deadnix",
  }) do
    tools[name] =
      { executable = fn.executable(name) == 1, path = fn.exepath(name) }
  end
  local clients = {}
  for _, client in ipairs(vim.lsp.get_clients()) do
    clients[#clients + 1] = {
      id = client.id,
      name = client.name,
      initialized = client.initialized == true,
      cmd = type(client.config.cmd) == "table" and client.config.cmd or nil,
      root_dir = client.config.root_dir,
    }
  end
  local loaded = {}
  for _, name in ipairs({
    "mini.pick",
    "mini.pairs",
    "mini.completion",
    "nvim-treesitter-textobjects.move",
    "pins",
    "lint",
    "ui.statusline",
    "ui.vc-gutter",
    "ui.blame",
  }) do
    loaded[name] = package.loaded[name] ~= nil
  end
  return {
    version = vim.version(),
    progpath = vim.v.progpath,
    runtimepath = vim.o.runtimepath,
    packpath = vim.o.packpath,
    appname = vim.env.NVIM_APPNAME,
    stdpaths = {
      config = fn.stdpath("config"),
      data = fn.stdpath("data"),
      state = fn.stdpath("state"),
      cache = fn.stdpath("cache"),
    },
    path = vim.env.PATH,
    tools = tools,
    clients = clients,
    loaded = loaded,
    messages = api.nvim_exec2("messages", { output = true }).output,
    mode = api.nvim_get_mode().mode,
    file = api.nvim_buf_get_name(0),
    cursor = api.nvim_win_get_cursor(0),
  }
end

_G.PoincareBenchmark = M
return M
