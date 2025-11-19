{craneLib, ...}: let
  src = craneLib.cleanCargoSource (craneLib.path ../../../.);

  cargoArtifacts = craneLib.buildDepsOnly {
    inherit src;
    doCheck = false;
  };
in
  craneLib.buildPackage {
    inherit src cargoArtifacts;
    pname = "poincare";
    doCheck = false;
    CARGO_PROFILE = "release";
  }
