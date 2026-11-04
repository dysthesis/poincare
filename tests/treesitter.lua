local MiniTest = require("mini.test")
local child = MiniTest.new_child_neovim()
local eq = MiniTest.expect.equality
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart()
      child.lua([[vim.opt.packpath:prepend(assert(vim.env.POINCARE_PACKPATH))]])
      child.cmd("packadd nvim-treesitter-grammar-nix")
      child.cmd("packadd vimplugin-nvim-treesitter-queries-nix")
    end,
    post_once = child.stop,
  },
})

T["Nix pipe chains parse and highlight as whole operators"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, {
    "let f = x: x; in {",
    "  forward = 1 |> f |> f;",
    "  backward = f <| f <| 1;",
    "}",
  })
  child.cmd("setfiletype nix")
  eq(
    child.lua([[
    vim.treesitter.start(0, "nix")
    local root = vim.treesitter.get_parser(0, "nix"):parse()[1]:root()
    local query = assert(vim.treesitter.query.get("nix", "highlights"))
    local operators = {}
    for id, node in query:iter_captures(root, 0) do
      local text = vim.treesitter.get_node_text(node, 0)
      if text == "|>" or text == "<|" then
        operators[#operators + 1] = { text, node:type(), query.captures[id] }
      end
    end
    return { has_error = root:has_error(), operators = operators }
  ]]),
    {
      has_error = false,
      operators = {
        { "|>", "|>", "operator" },
        { "|>", "|>", "operator" },
        { "<|", "<|", "operator" },
        { "<|", "<|", "operator" },
      },
    }
  )
end

return T
