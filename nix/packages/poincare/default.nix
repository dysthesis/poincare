{
  self,
  inputs,
  pkgs,
  lib,
  ...
}: let
  name = "poincare";
  optPlugins = import ./plugins {inherit pkgs inputs lib;};
  extraPackages = with pkgs; [
    ripgrep
    fd
    uutils-coreutils-noprefix
    tree-sitter
  ];

  buildFennel = pkgs.callPackage ./fennel.nix {};
  configDir = buildFennel {
    pname = "${name}-cfg";
    src = self;
    compileOnlyDirs = ["fnl/lib"];
  };
in
  pkgs.callPackage ./wrapper.nix {
    inherit
      optPlugins
      extraPackages
      name
      configDir
      ;

    meta.mainProgram = "nvim";
  }
