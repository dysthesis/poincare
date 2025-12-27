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
    builder {
      pname = "poincare-fennel";
      version = "0.1.0";
      compileOnlyDirs = ["fnl/lib"];
      src = ../..;
    };
}
