{
  pkgs,
  craneLib,
  ...
}: let
  src = craneLib.cleanCargoSource (craneLib.path ../../../.);

  commonArgs = {
    inherit src;

    strictDeps = true;

    buildInputs = [
      pkgs.luajit
    ];

    # Build-time tools; this is where `pkg-config` must be.
    nativeBuildInputs = [
      pkgs.pkg-config
    ];
  };

  cargoArtifacts = craneLib.buildDepsOnly (commonArgs
    // {
      pname = "poincare-deps";
      doCheck = false;
    });
in
  craneLib.buildPackage (commonArgs
    // {
      inherit cargoArtifacts;
      pname = "poincare";
      doCheck = false;
      CARGO_PROFILE = "release";
    })
