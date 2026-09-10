require("lz.n").load({
  "mini.completion",
  lazy = false,

  after = function()
    vim.o.pumborder = "rounded"
    vim.opt.completeopt = {
      "menu",
      "popup",
      "menuone",
      "noinsert",
      "fuzzy",
    }

    vim.api.nvim_set_hl(0, "PmenuBorder", {
      link = "FloatBorder",
    })

    require("mini.completion").setup({
      delay = {
        completion = 30,
        info = 100,
        signature = 50,
      },

      lsp_completion = {
        source_func = "omnifunc",
        auto_setup = false,
      },

      window = {
        info = {
          height = 30,
          width = 50,
          border = "single",
        },
        signature = {
          height = 30,
          width = 80,
          border = "single",
        },
      },
    })
  end,
})
