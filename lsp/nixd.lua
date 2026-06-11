---@type vim.lsp.Config
-- io.popen('hostname') here cost 4.3ms of every source (measured); the
-- libuv call returns the same string without forking a shell.
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
      formatting = {
        command = { 'alejandra' },
      },
      options = {
        nixos = {
          expr = '(builtins.getFlake ("git+file://" + toString ./.)).nixosConfigurations.' .. hostname .. '.options',
        },
      },
    },
  },
}
