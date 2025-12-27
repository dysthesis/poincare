{
  self,
  inputs,
  pkgs,
  lib,
  ...
}: let
  name = "poincare";
  optPlugins =
    (import ./plugins {inherit pkgs inputs lib;})
    ++ [pkgs.vimPlugins.nvim-treesitter.withAllGrammars];
  startPlugins = with pkgs.vimPlugins; [
    lz-n
    lzn-auto-require
    (pkgs.vimUtils.buildVimPlugin {
      name = "profile.nvim";
      src = pkgs.fetchFromGitHub {
        owner = "stevearc";
        repo = "profile.nvim";
        rev = "30433d7513f0d14665c1cfcea501c90f8a63e003";
        sha256 = "sha256-2Mk6VbC+K/WhTWF+yHyDhQKJhTi2rpo8VJsnO7ofHXs=";
      };
    })
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
