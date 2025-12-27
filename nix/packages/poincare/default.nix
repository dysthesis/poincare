{
  self,
  inputs,
  pkgs,
  lib,
  ...
}: let
  name = "poincare";
  optPlugins = import ./plugins {inherit pkgs inputs lib;};
  startPlugins = with pkgs.vimPlugins; [
    lz-n
    lzn-auto-require
    nvim-treesitter.withAllGrammars
  ];
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
    extraDirs = [
      "after"
    ];
  };
in
  pkgs.callPackage ./wrapper.nix {
    inherit
      optPlugins
      extraPackages
      name
      configDir
      startPlugins
      ;

    meta.mainProgram = "nvim";
  }
