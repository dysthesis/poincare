require("lz.n").load({
  "mini.completion",
  event = { "InsertEnter", "CmdlineEnter" },
  after = function()
    vim.o.pumborder = "rounded"
    vim.opt.completeopt = { "menuone", "noinsert", "fuzzy" }
    vim.api.nvim_set_hl(0, "PmenuBorder", { link = "FloatBorder" })
    require("mini.icons").tweak_lsp_kind("prepend")
    require("mini.completion").setup({
      window = {
        info = { height = 30, width = 100, border = "single" },
        signature = { height = 30, width = 100, border = "single" },
      },
    })
  end,
})
