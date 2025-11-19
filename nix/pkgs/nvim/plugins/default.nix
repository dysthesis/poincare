{
  craneLib,
  commonArgs,
  cargoArtifacts,
  pkgs,
  inputs,
  lib,
  ...
}: let
  inherit (lib) mapAttrsToList;
  inherit (builtins) isAttrs;

  inherit
    (lib.babel.nvim)
    mapPlugins
    mkNvimPlugin
    ;

  poincare = pkgs.callPackage ../../poincare {inherit craneLib pkgs commonArgs cargoArtifacts;};

  npins = import ./npins;
  mkNpins = mapAttrsToList (
    pname: src:
      mkNvimPlugin {
        inherit pkgs src pname;
        version = src.revision;
      }
  );
  builtNpins = mkNpins npins;

  lazy-plugins = with pkgs.vimPlugins;
    [
      mini-pick
      mini-extra
      mini-ai

      (nvim-treesitter.withPlugins (
        p:
          with p; [
            go
            css
            bash
            fish
            diff
            dockerfile
            asm
            disassembly
            git_config
            git_rebase
            gitignore
            python
            zig
            rust
            haskell
            nix
            lua
            c
            toml
            yaml
            markdown
            latex
            typst
          ]
      ))
    ]
    # ++ builtNpins
    ++ mapPlugins pkgs inputs "plugin-lazy";

  plugins =
    [poincare]
    ++ (map (
        x:
          if isAttrs x
          then x // {optional = true;}
          else {
            plugin = x;
            optional = true;
          }
      )
      lazy-plugins)
    # bleeding-edge plugins from flake inputs
    ++ mapPlugins pkgs inputs "plugin:"
    ++ (with pkgs.vimPlugins; [lz-n]);
in
  plugins
