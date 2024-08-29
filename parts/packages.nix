{
  inputs,
  lib,
  ...
}: {
  perSystem = {
    system,
    ...
  }: let
    neovim-overlay = import ../nix/neovim-overlay.nix {
      inherit lib inputs;
    };

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
}
