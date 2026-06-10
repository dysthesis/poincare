{
  self,
  pkgs,
  lib,
}: rec {
  default = poincare;
  poincare = pkgs.callPackage ./poincare {
    inherit
      pkgs
      lib
      self
      ;
  };
}
