require("lz.n").load({
  "mini.completion",
  event = { "InsertEnter", "CmdlineEnter" },
  after = function()
    require("mini.completion").setup({
      window = {
        info = { height = 30, width = 100, border = "single" },
        signature = { height = 30, width = 100, border = "single" },
      },
    })
  end,
})
