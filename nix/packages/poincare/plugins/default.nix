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
      lackluster-nvim # Colour scheme
      mini-extra # Extra utilties for the mini-* plugins
      mini-icons # Icons provider
      mini-pick # Picker menu
      smart-splits-nvim # Unified split management binding with tmux
      vim-tmux-navigator # Unified navigation binding with tmux
      blink-cmp # Fast completion
      ultimate-autopair-nvim # Smarter autopairs that recognises more patterns
      conform-nvim # Asynchronous, automatic formatting
      inc-rename-nvim # LSP symbol renaming
      oil-nvim
    ]
    ++ builtNpins
    ++ mapPlugins pkgs inputs "plugin-lazy"
