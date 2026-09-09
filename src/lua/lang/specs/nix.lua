return {
  lsp = { either = { "nil", "nixd" } },
  formatters = { either = { "alejandra", "nixfmt" } },
  linters = { all = { "statix", "deadnix" } },
}
