{
  pkgs,
  inputs,
  lib,
  ...
}: let
  inherit (lib) mapAttrsToList;

  inherit
    (lib.attrsets)
    removeAttrs
    ;

  inherit
    (lib.babel.nvim)
    mapPlugins
    mkNvimPlugin
    ;

  # npins adds a __functor attribute for backward compatibility; drop it so
  # we only iterate actual pins when building plugin derivations.
  npins = removeAttrs (import ./npins) ["__functor"];
  mkNpins = mapAttrsToList (pname: src:
    mkNvimPlugin {
      inherit pkgs src pname;
      version = src.revision;
    });
  builtNpins = mkNpins npins;
in
  with pkgs.vimPlugins;
    [
      (nvim-treesitter.withPlugins (p:
        with p; [
          markdown
          rust
          go
          zig
          c
          nix
          lua
        ]))

      mini-pick
      mini-extra # For LSP-based pickers
      mini-surround

      smart-splits-nvim
      ultimate-autopair-nvim
      conform-nvim
      nvim-lint

      # Debugging
      nvim-nio
      nvim-dap
      nvim-dap-ui
      nvim-dap-virtual-text
    ]
    ++ builtNpins
    ++ mapPlugins pkgs inputs "plugin-lazy"
