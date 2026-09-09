{
  pkgs,
  lib,
  ...
}: let
  wrapper = pkgs.callPackage ./wrapper.nix {inherit lib;};
  extraPlugins = import ./plugins {inherit pkgs lib;};
  eagerPlugins = [extraPlugins.minimal-nvim];
in
  rec {
    poincare = wrapper.override {inherit eagerPlugins;};

    default = poincare;
  }
  # Pass through the derivation for the npins plugins
  // extraPlugins
