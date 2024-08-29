{
  inputs,
  lib,
  ...
}: let
  neovim-overlay = import ../nix/neovim-overlay.nix {
    inherit lib inputs;
  };
in {
  perSystem = {
    pkgs,
    system,
    ...
  }: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;

      overlays = [
        neovim-overlay
        inputs.gen-luarc.overlays.default
      ];
    };
    packages = rec {
      default = nvim;
      nvim = pkgs.nvim-pkg;
    };
  };
  flake.overlays.default = neovim-overlay;
}
