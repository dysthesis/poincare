require("lz.n").load({
  "mini.icons",
  lazy = false,

  after = function()
    local icons = require("mini.icons")

    icons.setup()
    icons.tweak_lsp_kind("prepend")
  end,
})
