{
  craneLib,
  commonArgs,
  cargoArtifacts,
  ...
}:
craneLib.cargoClippy (
  commonArgs
  // {
    inherit cargoArtifacts;
    cargoClippyExtraArgs = "--all-targets -- --deny warnings";
  }
)
