require("lz.n").load({
  "mini.icons",
  lazy = false,
  after = function()
    require("mini.icons").setup()
  end,
})
