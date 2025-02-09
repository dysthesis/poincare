{
  self,
  pkgs,
  lib,
  inputs,
  ...
}: let
  overlay = import ../overlay {inherit lib inputs self;};
  pkgs' = import inputs.nixpkgs {
    inherit (pkgs) system;
    overlays = [overlay];
  };
in rec {
  default = nvim;
  nvim = pkgs'.nvim-pkg;
}
