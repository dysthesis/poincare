{
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

  npins = import ./npins;
  mkNpins = mapAttrsToList (pname: src:
    mkNvimPlugin {
      inherit pkgs src pname;
      version = src.revision;
    });
  builtNpins = mkNpins npins;

  # Make sure we use the pinned nixpkgs instance for wrapNeovimUnstable,
  # otherwise it could have an incompatible signature when applying this overlay.
  # pkgs-wrapNeovim = inputs.nixpkgs.legacyPackages.${pkgs.system};
  # This is the helper function that builds the Neovim derivation.
  # mkNeovim = pkgs.callPackage ./mkNeovim.nix {inherit pkgs-wrapNeovim;};
  # A plugin can either be a package or an attrset, such as
  # { plugin = <plugin>; # the package, e.g. pkgs.vimPlugins.nvim-cmp
  #   config = <config>; # String; a config that will be loaded with the plugin
  #   # Boolean; Whether to automatically load the plugin as a 'start' plugin,
  #   # or as an 'opt' plugin, that can be loaded with `:packadd!`
  #   optional = <true|false>; # Default: false
  #   ...
  # }
  lazy-plugins = with pkgs.vimPlugins;
    [
      nvim-ufo
      promise-async

      neogen
      nui-nvim
      noice-nvim

      blink-cmp
      blink-compat
      friendly-snippets

      nvim-lspconfig
      lspsaga-nvim
      conform-nvim

      todo-comments-nvim
      harpoon2

      inc-rename-nvim

      rustaceanvim
      crates-nvim

      vimtex
      nabla-nvim

      zk-nvim
      leap-nvim

      mini-pick
      mini-surround
      mini-icons
      mini-ai
      mini-indentscope
      lz-n
      neogit
      diffview-nvim
      gitsigns-nvim
      oil-nvim
      ultimate-autopair-nvim
      (nvim-treesitter.withPlugins (
        p:
          with p; [
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
            toml
            yaml
            markdown
            latex
          ]
      ))
      nvim-treesitter-textobjects # https://github.com/nvim-treesitter/nvim-treesitter-textobjects/
      smart-splits-nvim
      nvim-lint
    ]
    ++ builtNpins
    ++ mapPlugins pkgs inputs "plugin-lazy";

  plugins = with pkgs.vimPlugins;
    [
    ]
    # Plugins that should be lazily loaded
    ++ map (
      x:
        if isAttrs x
        then
          x
          // {
            optional = true;
          }
        else {
          plugin = x;
          optional = true;
        }
    )
    lazy-plugins
    # bleeding-edge plugins from flake inputs
    ++ mapPlugins pkgs inputs "plugin:";
in
  plugins
