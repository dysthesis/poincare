require("lz.n").load({
  "mini.surround",
  event = "BufEnter",
  after = function()
    require("mini.surround").setup()
  end,
})
