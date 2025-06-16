return {
  filetypes = { 'zig', 'zon' },
  cmd = { 'zls' },
  root_markers = { 'build.zig', 'build.zig.zon', '.git' },
  settings = {
    zls = {
      -- Neovim already provides basic syntax highlighting
      semantic_tokens = 'partial',
    },
  },
}
