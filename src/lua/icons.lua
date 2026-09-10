require("lz.n").load({
  "mini.icons",
  event = "DeferredUIEnter",
  after = function()
    require("mini.icons").setup()
  end,
})
