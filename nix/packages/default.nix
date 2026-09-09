{
  pkgs,
  lib,
  ...
}: let
  wrapper = pkgs.callPackage ./wrapper.nix {inherit lib;};
  extraPlugins = import ./plugins {inherit pkgs lib;};
  eagerPlugins = with pkgs.vimPlugins; with extraPlugins; [minimal-nvim lz-n];
  lazyPlugins = with pkgs.vimPlugins; [conform-nvim];
in
  rec {
    poincare = wrapper.override {
      inherit
        eagerPlugins
        lazyPlugins
        ;
    };

    default = poincare;
  }
  # Pass through the derivation for the npins plugins
  // extraPlugins
