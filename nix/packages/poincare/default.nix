{
  self,
  inputs,
  pkgs,
  lib,
  ...
}: let
  name = "poincare";
  optPlugins =
    import ./plugins {inherit pkgs inputs lib;};
  startPlugins = with pkgs.vimPlugins; [
    lz-n
    lzn-auto-require
    plenary-nvim
    nvim-treesitter.withAllGrammars
  ];

  extraPackages = with pkgs; [
    ripgrep
    fd
    uutils-coreutils-noprefix
    tree-sitter
  ];

  codelldbExt = pkgs.vscode-extensions.vadimcn.vscode-lldb;
  codelldbPath = "${codelldbExt}/share/vscode/extensions/vadimcn.vscode-lldb/adapter/codelldb";
  liblldbName =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "liblldb.dylib"
    else "liblldb.so";
  liblldbPath = "${codelldbExt}/share/vscode/extensions/vadimcn.vscode-lldb/lldb/lib/${liblldbName}";

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

    extraWrapperArgs = [
      "--set"
      "CODELLDB_PATH"
      codelldbPath
      "--set"
      "LIBLLDB_PATH"
      liblldbPath
    ];

    meta.mainProgram = "nvim";
  }
