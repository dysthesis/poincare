{
  pkgs,
  inputs,
  lib,
  ...
}:
let
  nvimWrapper = import ./wrapper.nix { inherit pkgs; };
in
nvimWrapper.withConfig {
  name = "poincare";
  plugins = import ./plugins { inherit pkgs inputs lib; };
  extraLua =
    # lua
    ''
      vim.notify("Works!")
    '';
}
