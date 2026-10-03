local MiniTest = require("mini.test")
local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({
        "--cmd",
        "lua vim.opt.runtimepath:prepend('/review/src'); vim.opt.packpath:prepend(vim.env.POINCARE_PACKPATH)",
        "-u",
        "/review/src/init.lua",
      })
      child.lua(
        "dofile('tests/regressions/lsp-display-server.lua'); DisplayServer.start()"
      )
    end,
    post_case = function()
      child.stop()
    end,
  },
})

local function last_request()
  return child.lua_get("DisplayServer.hints[#DisplayServer.hints]")
end

local function reply(id, label)
  child.lua(
    "local id, label = ...; DisplayServer.reply(id, DisplayServer.hint(label))",
    { id, label }
  )
end

local function refresh()
  child.lua("DisplayServer.refresh()")
  return last_request()
end

local function hint_is(label)
  local text = child.lua_get("DisplayServer.text(DisplayServer.ns)")
  assert(
    text == " " .. label,
    "wrong native hint decorations: " .. vim.inspect(text)
  )
end

local function hints_empty()
  assert(
    child.lua_get("#DisplayServer.marks()") == 0,
    "old inlay extmarks remain"
  )
end

local function seed()
  reply(last_request(), ": original")
  hint_is(": original")
end

local function diagnostic_is(message)
  local text = child.lua_get("DisplayServer.text()")
  assert(text:find(message, 1, true), "diagnostic not displayed: " .. text)
end

local function enter_insert()
  child.type_keys("i")
  assert(
    child.lua_get("vim.api.nvim_get_mode().mode") == "i",
    "not in Insert mode"
  )
end

local function pending_empty_diagnostics()
  child.lua(
    "vim.lsp.inlay_hint.enable(false, { bufnr = DisplayServer.buf }); DisplayServer.diag_ns = vim.lsp.diagnostic.get_namespace(DisplayServer.client_id); DisplayServer.publish('retained diagnostic')"
  )
  diagnostic_is("retained diagnostic")
  assert(child.lua_get("#DisplayServer.diagnostic_marks()") > 0)
  enter_insert()
  child.lua("DisplayServer.publish(nil)")
  diagnostic_is("retained diagnostic")
  assert(child.lua_get("#vim.diagnostic.get(DisplayServer.buf)") == 0)
  assert(
    child.lua_get("vim.tbl_isempty(vim.diagnostic.count(DisplayServer.buf))")
  )
end

local function diagnostics_empty()
  assert(
    child.lua_get("#DisplayServer.diagnostic_marks()") == 0,
    "old diagnostic decorations remain"
  )
  assert(child.lua_get("DisplayServer.text()") == "")
end

local function empty_namespace_released()
  assert(
    child.lua_get(
      "not vim.list_contains(require('vim.diagnostic._store').get_buf_namespaces(DisplayServer.buf), DisplayServer.diag_ns)"
    ),
    "resolved empty namespace is still cached"
  )
end

T["same-version server refresh retains marks until the current replacement"] = function()
  seed()
  local version = child.lua_get("vim.lsp.util.buf_versions[DisplayServer.buf]")
  local previous = last_request()
  local current = refresh()
  assert(
    current ~= previous,
    "same-version refresh did not issue a replacement"
  )
  assert(
    child.lua_get("vim.lsp.util.buf_versions[DisplayServer.buf]") == version
  )
  hint_is(": original")
  child.cmd("redraw!")
  hint_is(": original")
  reply(current, ": replacement")
  hint_is(": replacement")
end

T["current empty and nil results clear marks and cache their version"] = function()
  for _, result in ipairs({ {}, vim.NIL }) do
    reply(last_request(), ": original")
    hint_is(": original")
    local current = refresh()
    hint_is(": original")
    child.lua(
      "local id, result = ...; DisplayServer.reply(id, result)",
      { current, result }
    )
    hints_empty()
    assert(
      child.lua_get("#vim.lsp.inlay_hint.get({ bufnr = DisplayServer.buf })")
        == 0
    )
    child.lua(
      "vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = DisplayServer.buf })"
    )
    assert(last_request() == current, "accepted empty result was not cached")
    refresh()
  end
end

T["canceled same-version errors and late empties cannot erase newer state"] = function()
  seed()
  local canceled = refresh()
  local current = refresh()
  assert(child.lua_get("DisplayServer.canceled[...]", { canceled }))
  child.lua(
    "DisplayServer.reply(..., nil, { code = -32603, message = 'superseded server error' })",
    { canceled }
  )
  hint_is(": original")
  reply(current, ": current")
  hint_is(": current")

  local late = refresh()
  current = refresh()
  reply(current, ": newest")
  child.lua("DisplayServer.reply(..., {})", { late })
  hint_is(": newest")
  current = refresh()
  child.lua(
    "DisplayServer.reply(..., nil, { code = -32603, message = 'server error' })",
    { current }
  )
  hint_is(": newest")
end

for _, phase in ipairs({ "request", "cancel" }) do
  for _, outcome in ipairs({ "empty", "error" }) do
    T["canceled same-version " .. outcome .. " delivered inline during " .. phase] = function()
      seed()
      local canceled = refresh()
      local version =
        child.lua_get("vim.lsp.util.buf_versions[DisplayServer.buf]")
      -- ServerCancelled reaches the native provider; other errors are intercepted
      -- by Neovim's default handler before it sees the response.
      child.lua(
        "local id, phase, outcome = ...; DisplayServer.inline = { id = id, phase = phase, result = {}, err = outcome == 'error' and { code = -32802, message = 'inline canceled error' } or nil }",
        { canceled, phase, outcome }
      )
      local current = refresh()
      assert(current ~= canceled, "replacement was not issued")
      assert(child.lua_get("DisplayServer.canceled[...]", { canceled }))
      assert(child.lua_get("DisplayServer.inline_delivered") == 1)
      assert(
        child.lua_get("vim.lsp.util.buf_versions[DisplayServer.buf]") == version,
        "inline response did not use the same document version"
      )
      hint_is(": original")
      child.lua(
        "vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = DisplayServer.buf })"
      )
      assert(
        last_request() == current,
        "inline canceled response lost the pending replacement"
      )
      reply(current, ": replacement after inline " .. outcome)
      hint_is(": replacement after inline " .. outcome)
      child.lua(
        "vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = DisplayServer.buf })"
      )
      assert(
        last_request() == current,
        "inline canceled response corrupted replacement bookkeeping"
      )
    end
  end
end

T["failed request issuance keeps display and permits a current retry"] = function()
  seed()
  local previous = last_request()
  child.lua("DisplayServer.fail_next_hint = true; DisplayServer.refresh()")
  assert(last_request() == previous)
  hint_is(": original")
  local current = refresh()
  assert(current ~= previous, "failed issuance blocked the replacement")
  reply(current, ": retry")
  hint_is(": retry")
end

T["older document results cannot clear hints while the edited version is pending"] = function()
  seed()
  local stale = refresh()
  local version = child.lua_get("vim.lsp.util.buf_versions[DisplayServer.buf]")
  local requests = child.lua_get("#DisplayServer.hints")
  child.type_keys("A", " ", "<Esc>")
  child.lua(
    "local requests = ...; assert(vim.wait(1000, function() return #DisplayServer.hints > requests end))",
    { requests }
  )
  local current = last_request()
  assert(current ~= stale, "edit did not issue a new-version request")
  assert(
    child.lua_get("vim.lsp.util.buf_versions[DisplayServer.buf]") ~= version
  )
  child.lua("DisplayServer.reply(..., {})", { stale })
  hint_is(": original")
  reply(current, ": edited")
  hint_is(": edited")
end

T["hidden refresh cancels requests without clearing and refreshes on BufWinEnter"] = function()
  seed()
  local canceled = refresh()
  child.cmd("enew!")
  child.lua("DisplayServer.refresh()")
  assert(last_request() == canceled, "hidden buffer requested hints")
  child.lua("DisplayServer.reply(..., {})", { canceled })
  hint_is(": original")
  child.lua("vim.api.nvim_set_current_buf(DisplayServer.buf)")
  local current = last_request()
  assert(current ~= canceled, "hidden same-version cache was not invalidated")
  hint_is(": original")
  reply(current, ": visible")
  hint_is(": visible")
end

T["disable detach and close still clear immediately with requests pending"] = function()
  seed()
  local pending = refresh()
  child.lua("vim.lsp.inlay_hint.enable(false, { bufnr = DisplayServer.buf })")
  hints_empty()
  reply(pending, ": disabled")
  hints_empty()

  child.lua("vim.lsp.inlay_hint.enable(true, { bufnr = DisplayServer.buf })")
  reply(last_request(), ": enabled")
  hint_is(": enabled")
  pending = refresh()
  child.lua(
    "vim.lsp.buf_detach_client(DisplayServer.buf, DisplayServer.client_id)"
  )
  hints_empty()
  reply(pending, ": detached")
  hints_empty()

  child.lua(
    "vim.lsp.buf_attach_client(DisplayServer.buf, DisplayServer.client_id)"
  )
  reply(last_request(), ": attached")
  hint_is(": attached")
  refresh()
  child.cmd("enew! | bunload! /work/display.txt")
  assert(
    child.lua_get("vim.api.nvim_buf_is_loaded(DisplayServer.buf)") == false
  )
  hints_empty()
end

T["supported synchronous servers and customized handlers replace and clear hints"] = function()
  seed()
  child.lua([[
    local client = vim.lsp.get_client_by_id(DisplayServer.client_id)
    DisplayServer.handled = {}
    client.handlers['textDocument/inlayHint'] = function(err, result, ctx, config)
      table.insert(DisplayServer.handled, ctx.request_id)
      return vim.lsp.handlers['textDocument/inlayHint'](err, result, ctx, config)
    end
    DisplayServer.synchronous = DisplayServer.hint(': synchronous')
    DisplayServer.refresh()
  ]])
  hint_is(": synchronous")
  child.lua("DisplayServer.synchronous = {}; DisplayServer.refresh()")
  hints_empty()
  assert(child.lua_get("#DisplayServer.handled") == 2)
  local current = last_request()
  child.lua(
    "vim.api.nvim_exec_autocmds('BufWinEnter', { buffer = DisplayServer.buf })"
  )
  assert(last_request() == current, "synchronous empty was not cached")
  child.lua(
    "DisplayServer.synchronous = DisplayServer.hint(': reseeded'); DisplayServer.refresh()"
  )
  hint_is(": reseeded")
  child.lua("DisplayServer.synchronous = vim.NIL; DisplayServer.refresh()")
  hints_empty()
  assert(child.lua_get("#DisplayServer.handled") == 4)
end

T["latest pushed diagnostics and options are deferred through CursorHoldI until InsertLeave"] = function()
  child.lua(
    "vim.lsp.inlay_hint.enable(false, { bufnr = DisplayServer.buf }); DisplayServer.publish('original diagnostic')"
  )
  diagnostic_is("original diagnostic")
  enter_insert()
  child.lua(
    "DisplayServer.publish('intermediate diagnostic'); DisplayServer.publish('latest diagnostic')"
  )
  diagnostic_is("original diagnostic")
  assert(
    child.lua_get("vim.diagnostic.get(DisplayServer.buf)[1].message")
      == "latest diagnostic"
  )
  child.lua(
    "vim.api.nvim_exec_autocmds('CursorHoldI', { buffer = DisplayServer.buf })"
  )
  diagnostic_is("original diagnostic")
  child.type_keys("<Esc>")
  diagnostic_is("latest diagnostic")
  assert(
    not child
      .lua_get("DisplayServer.text()")
      :find("original diagnostic", 1, true)
  )

  enter_insert()
  child.lua(
    "DisplayServer.publish('discarded diagnostic'); DisplayServer.publish(nil)"
  )
  diagnostic_is("latest diagnostic")
  child.lua(
    "vim.api.nvim_exec_autocmds('CursorHoldI', { buffer = DisplayServer.buf })"
  )
  diagnostic_is("latest diagnostic")
  assert(child.lua_get("#vim.diagnostic.get(DisplayServer.buf)") == 0)
  child.type_keys("<Esc>")
  assert(
    child.lua_get("DisplayServer.text()") == "",
    "latest empty update did not clear"
  )

  child.lua(
    "DisplayServer.publish('options control'); DisplayServer.diag_ns = vim.lsp.diagnostic.get_namespace(DisplayServer.client_id)"
  )
  enter_insert()
  child.lua(
    "vim.diagnostic.set(DisplayServer.diag_ns, DisplayServer.buf, { { lnum = 0, col = 0, message = 'latest options' } }, { virtual_text = { prefix = 'LATEST' } })"
  )
  diagnostic_is("options control")
  child.type_keys("<Esc>")
  diagnostic_is("LATEST")
  diagnostic_is("latest options")
end

T["update_in_insert true and explicit hide reset disable remain immediate"] = function()
  child.lua(
    "vim.lsp.inlay_hint.enable(false, { bufnr = DisplayServer.buf }); DisplayServer.diag_ns = vim.lsp.diagnostic.get_namespace(DisplayServer.client_id); DisplayServer.publish('original')"
  )
  enter_insert()
  child.lua(
    "vim.diagnostic.config({ update_in_insert = true }); DisplayServer.publish('immediate')"
  )
  diagnostic_is("immediate")
  child.lua("DisplayServer.publish(nil)")
  assert(child.lua_get("DisplayServer.text()") == "")

  for _, action in ipairs({
    "vim.diagnostic.hide(DisplayServer.diag_ns, DisplayServer.buf)",
    "vim.diagnostic.reset(DisplayServer.diag_ns, DisplayServer.buf)",
    "vim.diagnostic.enable(false, { bufnr = DisplayServer.buf, ns_id = DisplayServer.diag_ns })",
  }) do
    child.lua("DisplayServer.publish('explicit control')")
    diagnostic_is("explicit control")
    child.lua(
      "vim.diagnostic.config({ update_in_insert = false }); DisplayServer.publish('pending')"
    )
    diagnostic_is("explicit control")
    child.lua(action)
    assert(
      child.lua_get("DisplayServer.text()") == "",
      "explicit clearing was deferred"
    )
    child.lua(
      "vim.diagnostic.config({ update_in_insert = true }); vim.diagnostic.enable(true, { bufnr = DisplayServer.buf, ns_id = DisplayServer.diag_ns })"
    )
  end
  child.type_keys("<Esc>")
end

for name, action in pairs({
  ["buffer hide"] = "vim.diagnostic.hide(nil, DisplayServer.buf)",
  ["global hide"] = "vim.diagnostic.hide()",
  ["buffer reset"] = "vim.diagnostic.reset(nil, DisplayServer.buf)",
  ["global reset"] = "vim.diagnostic.reset()",
  ["buffer disable"] = "vim.diagnostic.enable(false, { bufnr = DisplayServer.buf })",
  ["global disable"] = "vim.diagnostic.enable(false)",
}) do
  T["deferred empty diagnostics support unscoped " .. name] = function()
    pending_empty_diagnostics()
    child.lua(action)
    diagnostics_empty()
    empty_namespace_released()
    child.type_keys("<Esc>")
    diagnostics_empty()
    assert(child.lua_get("#vim.diagnostic.get(DisplayServer.buf)") == 0)
    if name:find("disable", 1, true) then
      child.lua("DisplayServer.publish('disabled replacement')")
      assert(child.lua_get("#vim.diagnostic.get(DisplayServer.buf)") == 1)
      diagnostics_empty()
    end
  end
end

for _, scope in ipairs({ "global", "namespace" }) do
  T["deferred empty diagnostics respond immediately to " .. scope .. " insert config"] = function()
    pending_empty_diagnostics()
    child.lua(
      "local scope = ...; vim.diagnostic.config({ update_in_insert = true }, scope == 'namespace' and DisplayServer.diag_ns or nil)",
      { scope }
    )
    diagnostics_empty()
    empty_namespace_released()
    child.type_keys("<Esc>")
    diagnostics_empty()
  end
end

for _, scope in ipairs({ "buffer", "global" }) do
  T["show-all with immediate options resolves deferred empty " .. scope .. " diagnostics"] = function()
    pending_empty_diagnostics()
    child.lua(
      "local scope = ...; vim.diagnostic.show(nil, scope == 'buffer' and DisplayServer.buf or nil, nil, { update_in_insert = true })",
      { scope }
    )
    diagnostics_empty()
    empty_namespace_released()
    child.type_keys("<Esc>")
    diagnostics_empty()
  end
end

T["resolving a deferred empty does not discard newer nonempty diagnostics or options"] = function()
  pending_empty_diagnostics()
  child.lua(
    "vim.diagnostic.set(DisplayServer.diag_ns, DisplayServer.buf, { { lnum = 0, col = 0, message = 'newest nonempty' } }, { virtual_text = { prefix = 'NEWEST' } })"
  )
  diagnostic_is("retained diagnostic")
  assert(child.lua_get("#vim.diagnostic.get(DisplayServer.buf)") == 1)
  child.type_keys("<Esc>")
  diagnostic_is("newest nonempty")
  diagnostic_is("NEWEST")
  assert(child.lua_get("#vim.diagnostic.get(DisplayServer.buf)") == 1)
  child.lua("vim.diagnostic.hide()")
  diagnostics_empty()
  assert(child.lua_get("#vim.diagnostic.get(DisplayServer.buf)") == 1)
end

T["wiping a buffer drops its deferred empty diagnostic namespace"] = function()
  pending_empty_diagnostics()
  child.lua("vim.api.nvim_buf_delete(DisplayServer.buf, { force = true })")
  assert(
    child.lua_get(
      "not vim.list_contains(require('vim.diagnostic._store').get_bufnrs(), DisplayServer.buf)"
    ),
    "wiped buffer remains in the diagnostic inventory"
  )
end

return T
