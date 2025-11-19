{
  craneLib,
  commonArgs,
  cargoArtifacts,
  ...
}:
craneLib.cargoDoc (
  commonArgs
  // {
    inherit cargoArtifacts;
    # This can be commented out or tweaked as necessary, e.g. set to
    # `--deny rustdoc::broken-intra-doc-links` to only enforce that lint
    env.RUSTDOCFLAGS = "--deny warnings";
  }
)
