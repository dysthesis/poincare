return {
  lsp = "rust_analyzer",
  formatters = { "rustfmt" },
  linters = "clippy",
  setup = function()
    require("lz.n").load({
      "ferris-nvim",
      ft = "rust",
      keys = {
        {
          "gm",
          function()
            require("ferris.methods.view_memory_layout")()
          end,
          desc = "View Memory Layout",
        },
        {

          "gS",
          function()
            require("ferris.methods.expand_macro")()
          end,
          desc = "Expand Macro",
        },
        {
          "gM",
          function()
            require("ferris.methods.view_mir")()
          end,
          desc = "Expand MIR",
        },
        {
          "gh",
          function()
            require("ferris.methods.view_hir")()
          end,
          desc = "Expand HIR",
        },
        {
          "gD",
          function()
            require("ferris.methods.open_documentation")()
          end,
          desc = "Go to documentation",
        },
      },
      after = function()
        require("ferris").setup()
      end,
    })
  end,
}
