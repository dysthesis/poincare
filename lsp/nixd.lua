local file = io.popen('hostname')
if file == nil then
  return
end

local hostname = file:read('*a') or ''
file:close()
local hostname = string.gsub(hostname, '\n$', '')

return {
  cmd = { 'nixd' },
  filetypes = { 'nix' },
  root_markers = { 'flake.nix', 'git' },
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
