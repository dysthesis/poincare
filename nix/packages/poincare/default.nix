{
  pkgs,
  lib,
  self,
  # Overridable so packages.poincare-nightly can swap in nightly Neovim.
  neovim-unwrapped ? pkgs.neovim-unwrapped,
}: let
  name = "poincare";
  optPlugins = import ./plugins {inherit pkgs lib;};
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
  ];

  # Interpolate files individually so the whole repo isn't a build input;
  # doc/bench edits must not rebuild the wrapper.
  configDir = pkgs.runCommand "${name}-cfg" {} ''
    mkdir -p "$out"
    cp ${../../../init.lua} "$out/init.lua"
    cp -r ${../../../lsp} "$out/lsp"
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

    inherit neovim-unwrapped;

    extraPassthru = {
      checks = self.checks.${pkgs.stdenv.hostPlatform.system};
      # Test-only harness; tests inject it via MINI_TEST_PATH, so release
      # closure excludes it.
      miniTest = pkgs.vimPlugins.mini-test;
    };

    meta.mainProgram = "nvim";
  }
