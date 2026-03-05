{
  inputs,
  pkgs,
  lib,
  self,
  ...
}: let
  name = "poincare";
  optPlugins =
    import ./plugins {inherit pkgs inputs lib;};
  startPlugins = with pkgs.vimPlugins; [
    lz-n
    lzn-auto-require
  ];

  extraPackages = with pkgs; [
    ripgrep
    fd
    uutils-coreutils-noprefix
    tree-sitter
  ];

  codelldbExt = pkgs.vscode-extensions.vadimcn.vscode-lldb;
  codelldbPath = 
    "${codelldbExt}/share/vscode/extensions/vadimcn.vscode-lldb/adapter/codelldb";
  liblldbName =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "liblldb.dylib"
    else "liblldb.so";
  liblldbPath = 
    "${codelldbExt}/share/vscode/extensions/vadimcn.vscode-lldb/lldb/lib/${liblldbName}";

  configDir = pkgs.runCommand "${name}-cfg" {} ''
    mkdir -p "$out"
    cp ${../../..}/init.lua "$out/init.lua"

    # Copy common Neovim runtime directories when present in the repo root.
    for d in \
      after \
      autoload \
      colors \
      compiler \
      doc \
      ftdetect \
      ftplugin \
      indent \
      keymap \
      lua \
      pack \
      plugin \
      queries \
      rplugin \
      spell \
      syntax \
      syntax_checkers \
      tutor \
      snippets \
    ; do
      src="${../../..}/$d"
      if [ -d "$src" ]; then
        cp -r "$src" "$out/"
      fi
    done
  '';
in
  pkgs.callPackage ./wrapper.nix {
    inherit
      optPlugins
      extraPackages
      name
      configDir
      startPlugins
      ;
    neovim-unwrapped =
      inputs.neovim-nightly-overlay.packages.${pkgs.system}.default;

    extraWrapperArgs = [
      "--set"
      "CODELLDB_PATH"
      codelldbPath
      "--set"
      "LIBLLDB_PATH"
      liblldbPath
    ];

    extraPassthru = {
      checks = self.checks.${pkgs.system};
    };

    meta.mainProgram = "nvim";
  }
