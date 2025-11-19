{
  craneLib,
  pkgs,
  inputs,
  commonArgs,
  cargoArtifacts,
  ...
}:
let

  inherit (pkgs) callPackage;
in
rec {
  poincare = callPackage ./poincare.nix {
    inherit
      craneLib
      pkgs
      commonArgs
      cargoArtifacts
      ;
  };
  default = poincare;
}
