{ craneLib, src, ... }:
craneLib.cargoDeny {
  inherit src;
}
