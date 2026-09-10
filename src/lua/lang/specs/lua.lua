return {
  lsp = "lua-language-server",
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
