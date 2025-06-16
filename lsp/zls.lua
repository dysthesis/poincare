return {
  filetypes = { 'zig' },
  cmd = { 'zls' },
  settings = {
    zls = {
      -- Neovim already provides basic syntax highlighting
      semantic_tokens = 'partial',
    },
  },
}
