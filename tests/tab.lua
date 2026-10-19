local MiniTest = require("mini.test")
local root = vim.fs.dirname(
  vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))
)
local child = MiniTest.new_child_neovim()
local eq = MiniTest.expect.equality
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart()
      child.lua("vim.opt.runtimepath:prepend(...)", { root .. "/src" })
      child.lua("require('tab').setup()")
    end,
    post_once = child.stop,
  },
})

T["literal Tab works without the optional snippet API"] = function()
  child.lua("vim.snippet = nil; vim.o.expandtab = false")
  child.type_keys("i", "<Tab>", "x", "<Esc>")
  eq(child.api.nvim_buf_get_lines(0, 0, -1, false), { "\tx" })
end

T["normal Tab toggles both open and closed containing folds"] = function()
  child.api.nvim_buf_set_lines(
    0,
    0,
    -1,
    false,
    { "one", "two", "three", "four" }
  )
  child.cmd("setlocal foldmethod=manual foldenable")
  child.cmd("2,3fold")
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  eq(child.fn.foldclosed(2), 2)
  child.type_keys("<Tab>")
  eq(child.fn.foldclosed(2), -1)
  child.type_keys("<Tab>")
  eq(child.fn.foldclosed(2), 2)
end

T["normal Tab and Backtab retain native jump-list directions"] = function()
  child.api.nvim_buf_set_lines(
    0,
    0,
    -1,
    false,
    { "one", "two", "three", "four" }
  )
  child.cmd("setlocal nofoldenable")
  child.cmd("normal! 4G")
  child.type_keys("<S-Tab>")
  eq(child.fn.line("."), 1)
  child.type_keys("<Tab>")
  eq(child.fn.line("."), 4)
end

T["select and insert mappings jump through real snippets in both directions"] = function()
  child.type_keys("i")
  child.lua([[vim.snippet.expand("${1:first} ${2:second} $0")]])
  child.type_keys("<Tab>", "X", "<S-Tab>", "Y", "<Esc>")
  eq(child.api.nvim_buf_get_lines(0, 0, -1, false), { "Y X " })
end

T["completion selection takes priority over an active snippet"] = function()
  child.type_keys("i")
  child.lua([[vim.snippet.expand("${1:first} ${2:second} $0")]])
  child.type_keys("f")
  child.lua(
    [[vim.o.completeopt = "menuone,noinsert,noselect"; vim.fn.complete(1, { "first", "final" })]]
  )
  eq(child.fn.pumvisible(), 1)
  child.type_keys("<Tab>")
  eq(child.fn.complete_info({ "selected" }).selected, 0)
  eq(child.lua_get("vim.snippet.active({ direction = -1 })"), false)
  child.type_keys("<S-Tab>")
  eq(child.fn.complete_info({ "selected" }).selected, -1)
  child.type_keys("<C-e>", "<Tab>", "s")
  eq(child.lua_get("vim.snippet.active({ direction = -1 })"), true)
  child.lua([[vim.fn.complete(3, { "second", "sibling" })]])
  eq(child.fn.pumvisible(), 1)
  child.type_keys("<S-Tab>")
  eq(child.fn.complete_info({ "selected" }).selected, 1)
  eq(child.lua_get("vim.snippet.active({ direction = -1 })"), true)
  child.type_keys("<C-e>", "<Esc>")
end

return T
