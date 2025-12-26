{
  self,
  pkgs,
  lib,
  inputs,
  ...
}: rec {
  default = poincare;
  poincare = pkgs.callPackage ./poincare {
    inherit
      pkgs
      inputs
      lib
      self
      ;
  };

  fennelBuilt = let
    builder = pkgs.callPackage ./poincare/fennel.nix {};
  in
    builder {src = ../..;};
}
