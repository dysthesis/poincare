{ craneLib, src, ... }:
craneLib.cargoFmt {
  inherit src;
}
