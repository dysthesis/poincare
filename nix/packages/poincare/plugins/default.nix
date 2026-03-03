{
  pkgs,
  inputs,
  lib,
  ...
}: let
  inherit (lib) mapAttrsToList;

  inherit
    (lib.babel.nvim)
    mapPlugins
    mkNvimPlugin
    ;

  npins = import ./npins;
  mkNpins = mapAttrsToList (pname: src:
    mkNvimPlugin {
      inherit pkgs src pname;
      version = src.revision;
    });
  builtNpins = mkNpins npins;
in
  with pkgs.vimPlugins;
    [
      blink-cmp
      plenary-nvim
      (nvim-treesitter.withPlugins (p:
        with p; [
          markdown
          rust
          go
          zig
          c
          nix
        ]))
    ]
    ++ builtNpins
    ++ mapPlugins pkgs inputs "plugin-lazy"
