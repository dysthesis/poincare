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
  leanTreeSitterGrammar = pkgs.tree-sitter.builtGrammars.tree-sitter-lean.overrideAttrs (_: {
    version = "0.2.0-unstable-2026-05-30";
    src = pkgs.fetchFromGitHub {
      owner = "Julian";
      repo = "tree-sitter-lean";
      rev = "1941d160719daabc7d9854539d59e5911ac3b152";
      hash = "sha256-UE+i/qnnRzulS9RDpevqvyoPTBZXVuwcLkFoWV2z8BM=";
    };
  });
  leanTreeSitterRuntime = pkgs.runCommand "nvim-treesitter-lean" {} ''
    mkdir -p "$out/parser" "$out/queries/lean"
    ln -s ${leanTreeSitterGrammar}/parser "$out/parser/lean.so"
    for query in ${leanTreeSitterGrammar}/queries/*.scm; do
      ln -s "$query" "$out/queries/lean/$(basename "$query")"
    done
  '';
  startPlugins = with pkgs.vimPlugins; [
    lz-n
    lzn-auto-require
    (nvim-treesitter.withPlugins (p:
      with p; [
        markdown
        rust
        go
        zig
        c
        nix
        lua
        just
        python
      ]))
    leanTreeSitterRuntime
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
      lsp \
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

    inherit (pkgs) neovim-unwrapped;

    extraWrapperArgs = [
      "--set"
      "CODELLDB_PATH"
      codelldbPath
      "--set"
      "LIBLLDB_PATH"
      liblldbPath
    ];

    extraPassthru = {
      checks = self.checks.${pkgs.stdenv.hostPlatform.system};
    };

    meta.mainProgram = "nvim";
  }
