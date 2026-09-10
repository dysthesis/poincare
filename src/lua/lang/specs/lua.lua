return {
  lsp = "lua-language-server",
  fold = true,
  formatters = {
    {
      "stylua",
      "--search-parent-directories",
      "--respect-ignores",
      "--stdin-filepath",
      "$FILENAME",
      "-",
    },
  },
  linters = "selene",
}
