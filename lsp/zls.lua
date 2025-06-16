return {
  filetypes = { 'zig' },
  cmd = { 'zls', 'zon' },
  root_markers = { 'build.zig', 'build.zig.zon', '.git' },
  settings = {
    zls = {
      -- Neovim already provides basic syntax highlighting
      semantic_tokens = 'partial',
    },
  },
}
