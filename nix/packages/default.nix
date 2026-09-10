{
  pkgs,
  lib,
  inputs,
  ...
}: let
  wrapper = pkgs.callPackage ./wrapper.nix {inherit lib;};
  extraPlugins = import ./plugins {inherit pkgs lib;};
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
  eagerPlugins = with pkgs.vimPlugins; [
    extraPlugins.minimal-nvim
    lz-n
    (nvim-treesitter.withPlugins (
      p:
        with p; [
          markdown
          rust
          go
          zig
          c
          (nix.overrideAttrs (_: {
            src = inputs.tree-sitter-nix;
            version = "0.0.0+rev=${inputs.tree-sitter-nix.shortRev}";
          }))
          lua
          just
          python
        ]
    ))
    leanTreeSitterRuntime
  ];
  lazyPlugins = with pkgs.vimPlugins; [
    mini-completion
    mini-icons
    mini-pick
    mini-extra
    nvim-lint
    nvim-treesitter-textobjects
  ];
in
  rec {
    poincare = wrapper.override {inherit eagerPlugins lazyPlugins;};
    default = poincare;
  }
  # Pass through the derivation for the npins plugins
  // extraPlugins
