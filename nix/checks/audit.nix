{
  craneLib,
  advisory-db,
  src,
  ...
}:
craneLib.cargoAudit {
  inherit src advisory-db;
}
