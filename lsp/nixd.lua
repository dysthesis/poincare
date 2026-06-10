---@type vim.lsp.Config
local hostname = vim.uv.os_gethostname()

return {
  cmd = { 'nixd' },
  filetypes = { 'nix' },
  root_markers = { 'flake.nix', '.git' },
  settings = {
    nixd = {
      nixpkgs = {
        expr = 'import <nixpkgs> { }',
      },
      formatting = { command = { 'alejandra' } },
      options = {
        nixos = {
          expr = '(builtins.getFlake ("git+file://" + toString ./.)).nixosConfigurations.' .. hostname .. '.options',
        },
      },
    },
  },
}
