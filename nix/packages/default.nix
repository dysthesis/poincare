{
  self,
  pkgs,
  lib,
  inputs,
  ...
}: rec {
  default = poincare;
  poincare = pkgs.callPackage ./poincare.nix {inherit pkgs inputs lib self;};
}
