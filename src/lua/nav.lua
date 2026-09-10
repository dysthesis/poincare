local function call(module, method, namespace)
  return function()
    local target = require(module)
    target = namespace and target[namespace] or target
    target[method]()
  end
end
require("lz.n").load({
  "smart-splits.nvim",
  keys = {
    { "<A-h>", call("smart-splits", "resize_left"), desc = "Resize left" },
    { "<A-j>", call("smart-splits", "resize_down"), desc = "Resize down" },
    { "<A-k>", call("smart-splits", "resize_up"), desc = "Resize up" },
    { "<A-l>", call("smart-splits", "resize_right"), desc = "Resize right" },
    {
      "<C-h>",
      call("smart-splits", "move_cursor_left"),
      desc = "Move cursor left",
    },
    {
      "<C-j>",
      call("smart-splits", "move_cursor_down"),
      desc = "Move cursor down",
    },
    {
      "<C-k>",
      call("smart-splits", "move_cursor_up"),
      desc = "Move cursor up",
    },
    {
      "<C-l>",
      call("smart-splits", "move_cursor_right"),
      desc = "Move cursor right",
    },
    {
      "<C-\\>",
      call("smart-splits", "move_cursor_previous"),
      desc = "Move cursor to previous split",
    },
  },
})
