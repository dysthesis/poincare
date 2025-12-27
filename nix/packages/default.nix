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
}
