{
  pkgs,
  craneLib,
  commonArgs,
  cargoArtifacts,
  self,
  lib,
  inputs,
  ...
}: let
  nvimWrapper = import ./wrapper.nix {inherit pkgs self;};
in
  nvimWrapper.withConfig {
    name = "poincare";
    plugins = import ./plugins {inherit pkgs craneLib commonArgs cargoArtifacts inputs lib;};
  }
