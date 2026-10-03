-- A controlled in-process LSP server using Neovim's supported cmd transport.
-- Requests travel through the real Client and native capability/diagnostic handlers.
local S = { requests = {}, hints = {}, canceled = {}, next_id = 0 }

local function deliver(request, result, err)
  if request.complete then
    request.complete(request.id)
  end
  request.callback(err, result ~= vim.NIL and result or nil, request.id)
end

local function inline_reply(phase, id)
  local response = S.inline
  if response and response.phase == phase and (not id or response.id == id) then
    S.inline = nil
    S.reply(response.id, response.result, response.err)
    S.inline_delivered = (S.inline_delivered or 0) + 1
  end
end

local function lifecycle_hook(phase, id)
  local hook = S[phase]
  if hook then
    S[phase] = nil
    hook(id)
  end
end

function S.cmd(dispatchers)
  S.dispatchers = dispatchers
  local closing = false
  return {
    request = function(method, params, callback, complete)
      if method == "textDocument/inlayHint" and S.fail_next_hint then
        S.fail_next_hint = nil
        return false
      end
      S.next_id = S.next_id + 1
      local request = {
        id = S.next_id,
        method = method,
        params = params,
        callback = callback,
        complete = complete,
      }
      S.requests[request.id] = request
      if method == "textDocument/inlayHint" then
        S.hints[#S.hints + 1] = request.id
        inline_reply("request")
        lifecycle_hook("on_request", request.id)
        if S.synchronous or S.synchronous_error then
          deliver(request, S.synchronous, S.synchronous_error)
        end
      else
        vim.schedule(function()
          if method == "initialize" then
            deliver(request, {
              capabilities = {
                positionEncoding = "utf-16",
                textDocumentSync = { openClose = true, change = 1 },
                inlayHintProvider = true,
              },
              serverInfo = { name = "poincare-display-test" },
            })
          else
            deliver(request, vim.NIL)
          end
        end)
      end
      return true, request.id
    end,
    notify = function(method, params)
      if method == "$/cancelRequest" then
        S.canceled[params.id] = true
        inline_reply("cancel", params.id)
        lifecycle_hook("on_cancel", params.id)
      end
      return true
    end,
    is_closing = function()
      return closing
    end,
    terminate = function()
      closing = true
      dispatchers.on_exit(0, 0)
    end,
  }
end

function S.hint(label)
  return {
    {
      position = { line = 0, character = 5 },
      label = label,
      paddingLeft = true,
    },
  }
end

function S.reply(id, result, err)
  -- Deliberately permit canceled and out-of-order replies like a remote server.
  deliver(assert(S.requests[id]), result, err)
end

function S.refresh()
  local _, err =
    S.dispatchers.server_request("workspace/inlayHint/refresh", vim.NIL)
  assert(not err, vim.inspect(err))
end

function S.request_type(id)
  local request = vim.lsp.get_client_by_id(S.client_id).requests[id]
  return request and request.type
end

function S.publish(message)
  local diagnostics = message
      and {
        {
          range = {
            start = { line = 0, character = 0 },
            ["end"] = { line = 0, character = 1 },
          },
          severity = 1,
          message = message,
        },
      }
    or {}
  S.dispatchers.notification("textDocument/publishDiagnostics", {
    uri = vim.uri_from_bufnr(S.buf),
    diagnostics = diagnostics,
  })
end

function S.start()
  vim.cmd.enew({ bang = true })
  S.buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(S.buf, "/work/display.txt")
  vim.api.nvim_buf_set_lines(S.buf, 0, -1, false, { "value = 1" })
  vim.b[S.buf].minicompletion_disable = true
  vim.wo.foldenable = false
  vim.lsp.inlay_hint.enable(true, { bufnr = S.buf })
  S.client_id = assert(vim.lsp.start({
    name = "poincare-display-test",
    cmd = S.cmd,
    root_dir = "/work",
    flags = { debounce_text_changes = 0 },
  }, { bufnr = S.buf }))
  assert(
    vim.wait(1000, function()
      return #S.hints > 0
    end),
    "initial native inlay request was not sent"
  )
  S.ns =
    assert(vim.api.nvim_get_namespaces()["nvim.lsp.inlay_hint:" .. S.client_id])
end

function S.marks()
  vim.cmd.redraw()
  return vim.api.nvim_buf_get_extmarks(S.buf, S.ns, 0, -1, { details = true })
end

function S.text(namespace)
  vim.cmd.redraw()
  local texts = {}
  for _, mark in
    ipairs(
      vim.api.nvim_buf_get_extmarks(
        S.buf,
        namespace or -1,
        0,
        -1,
        { details = true }
      )
    )
  do
    for _, chunk in ipairs(mark[4].virt_text or {}) do
      texts[#texts + 1] = chunk[1]
    end
  end
  return table.concat(texts)
end

function S.diagnostic_marks()
  vim.cmd.redraw()
  local ns = vim.lsp.diagnostic.get_namespace(S.client_id)
  local data = vim.diagnostic.get_namespace(ns).user_data
  local marks = {}
  for _, field in ipairs({
    "sign_ns",
    "underline_ns",
    "virt_text_ns",
    "virt_lines_ns",
  }) do
    if data[field] then
      vim.list_extend(
        marks,
        vim.api.nvim_buf_get_extmarks(
          S.buf,
          data[field],
          0,
          -1,
          { details = true }
        )
      )
    end
  end
  return marks
end

_G.DisplayServer = S
