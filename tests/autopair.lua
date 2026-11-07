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
      child.lua([[vim.opt.packpath:prepend(assert(vim.env.POINCARE_PACKPATH))]])
      child.cmd("packadd lz.n")
      child.lua("require('autopair')")
    end,
    post_once = child.stop,
  },
})

T["Rust lifetimes, labels and character literals stay as typed"] = function()
  child.bo.filetype = "rust"
  local text =
    [[fn f<'a>(x: &'a str) { 'outer: loop { let c = '\''; break 'outer; } }]]
  child.type_keys("i", text:gsub("<", "<lt>"), "<Esc>")
  eq(child.api.nvim_buf_get_lines(0, 0, -1, false), { text })
end

T["apostrophes neither skip existing quotes nor delete them on backspace"] = function()
  child.bo.filetype = "lua"
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "'" })
  child.type_keys("i", "'")
  eq(child.api.nvim_buf_get_lines(0, 0, -1, false), { "''" })
  child.type_keys("<BS>", "<Esc>")
  eq(child.api.nvim_buf_get_lines(0, 0, -1, false), { "'" })
end

T["brackets and double quotes still pair, skip and delete"] = function()
  child.type_keys("i", "(", '"')
  eq(child.api.nvim_buf_get_lines(0, 0, -1, false), { '("")' })
  eq(child.api.nvim_win_get_cursor(0), { 1, 2 })
  child.type_keys("x", '"', ")")
  eq(child.api.nvim_buf_get_lines(0, 0, -1, false), { '("x")' })
  eq(child.api.nvim_win_get_cursor(0), { 1, 5 })
  child.type_keys("<Esc>", "o", "(", "<BS>", "<Esc>")
  eq(child.api.nvim_buf_get_lines(0, 0, -1, false), { '("x")', "" })
end

T["command-line-first loading keeps apostrophes literal"] = function()
  child.type_keys(":", "'")
  eq(child.fn.getcmdline(), "'")
  child.type_keys("'", "<Left>", "<BS>")
  eq(child.fn.getcmdline(), "'")
  child.type_keys("<Esc>")
end

return T
