{
  pkgs,
  inputs,
  lib,
  self,
  ...
}:
let
  nvimWrapper = import ./wrapper.nix { inherit pkgs self; };
in
nvimWrapper.withConfig {
  name = "poincare";
  plugins = import ./plugins { inherit pkgs inputs lib; };
  withFennelSupport = true;
  includeRtpDirs = [
    "fnl/"
  ];
}
