local function call(module, method, namespace)
  return function()
    local target = require(module)
    target = namespace and target[namespace] or target
    target[method]()
  end
end

local function lsp(scope)
  return function()
    require("mini.extra").pickers.lsp({ scope = scope })
  end
end

require("lz.n").load({
  "mini.pick",
  cmd = "Pick",
  load = function(name)
    vim.cmd.packadd(name)
    vim.cmd.packadd("mini.extra")
  end,
  keys = {
    {
      "<leader>f",
      call("mini.pick", "files", "builtin"),
      desc = "Find [F]iles",
    },
    {
      "<leader>/",
      call("mini.pick", "grep_live", "builtin"),
      desc = "Find [G]rep",
    },
    {
      "<leader>d",
      call("mini.extra", "diagnostic", "pickers"),
      desc = "Find [D]iagnostics",
    },
    {
      "<leader>e",
      call("mini.extra", "explorer", "pickers"),
      desc = "File [E]xplorer",
    },
    {
      "<leader>g",
      call("mini.extra", "git_hunks", "pickers"),
      desc = "Find [G]it hunks",
    },
    { "<leader>s", lsp("document_symbol"), desc = "Find [S]ymbols" },
    {
      "<leader>S",
      lsp("workspace_symbol"),
      desc = "Find Workspace [S]ymbols",
    },
    { "<leader>r", lsp("references"), desc = "Find [R]eferences" },
    {
      "<leader>i",
      lsp("implementation"),
      desc = "Find [I]mplementation",
    },
    {
      "<leader>T",
      call("mini.extra", "treesitter", "pickers"),
      desc = "Find [T]reesitter nodes",
    },
  },
  after = function()
    local MiniPick = require("mini.pick")
    MiniPick.setup({
      mappings = {
        move_down = "<C-j>",
        move_up = "<C-k>",
      },
      window = {
        prompt_prefix = "   ",
        config = function()
          local floor, lines, columns = math.floor, vim.o.lines, vim.o.columns
          local height, width = floor(0.618 * lines), floor(0.618 * columns)
          return {
            anchor = "NW",
            border = "rounded",
            height = height,
            width = width,
            row = floor(0.5 * (lines - height)),
            col = floor(0.5 * (columns - width)),
          }
        end,
      },
    })
    vim.ui.select = MiniPick.ui_select
  end,
})
