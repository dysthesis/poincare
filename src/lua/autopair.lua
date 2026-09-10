require("lz.n").load({
  "mini.pairs",
  event = { "InsertEnter", "CmdlineEnter" },
  after = function()
    require("mini.pairs").setup({
      modes = { insert = true, command = true, terminal = true },
    })
  end,
})
