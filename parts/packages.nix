{
  inputs,
  lib,
  ...
}: let
  neovim-overlay = import ../nix/neovim-overlay.nix {
    inherit lib inputs;
  };
in {
  perSystem = {system, ...}: let
    pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = [
        neovim-overlay
        inputs.gen-luarc.overlays.default
      ];
    };
  in {
    packages = rec {
      default = nvim;
      nvim = pkgs.nvim-pkg;
    };
  };
  flake.overlays.default = neovim-overlay;
}
