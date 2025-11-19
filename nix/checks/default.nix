{
  lib,
  poincare,
  craneLib,
  commonArgs,
  cargoArtifacts,
  src,
  advisory-db,
  ...
}:
let
  inherit (lib) fold;
  defaultCheckArgs = {
    inherit
      craneLib
      commonArgs
      cargoArtifacts
      src
      advisory-db
      ;
  };

  mkCheck = name: {
    "poincare-${name}" = import (./. + "/${name}.nix") defaultCheckArgs;
  };

  checkNames = [
    "clippy"
    "doc"
    "fmt"
    "audit"
    "deny"
    "nextest"
  ];

  checks = fold (curr: acc: acc // mkCheck curr) { inherit poincare; } checkNames;
in
checks
