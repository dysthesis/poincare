{
  inputs,
  craneLib,
  pkgs,
  lib,
  self,
  commonArgs,
  cargoArtifacts,
  ...
}: let
  inherit (pkgs) callPackage;
in rec {
  poincare = callPackage ./poincare.nix {
    inherit craneLib pkgs commonArgs cargoArtifacts;
  };
  nvim = callPackage ./nvim {
    inherit pkgs inputs lib self craneLib commonArgs cargoArtifacts;
  };
  default = nvim;
}
