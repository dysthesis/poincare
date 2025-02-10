# This overlay, when applied to nixpkgs, adds the final neovim derivation to nixpkgs.
{
	self,
  inputs,
  lib,
}: final: _prev:
with final.pkgs.lib; let
  inherit
    (builtins)
    readDir
    attrNames
    concatStringsSep
    stringLength
    substring
    ;

  inherit
    (lib)
    filterAttrs
    ;

  inherit 
		(lib.babel.nvim) 
		mkNeovim
		mapPlugins
		;

  pkgs = final;

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
      nvim-ufo # Folding improvements
      promise-async # Dependency of nvim-ufo

      blink-cmp # Way faster completion UI
      friendly-snippets

      nvim-lspconfig
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
      (nvim-treesitter.withPlugins (p:
        with p; [
          rust
          nix
          lua
          toml
          yaml
          markdown
        ]))
      nvim-treesitter-textobjects # https://github.com/nvim-treesitter/nvim-treesitter-textobjects/
      vim-tmux-navigator
    ]
    ++ mapPlugins pkgs inputs "plugin-lazy";

  plugins = with pkgs.vimPlugins;
    [
    ]
    # Plugins that should be lazily loaded
    ++ map
    (x:
      if isAttrs x
      then
        x
        // {
          optional = true;
        }
      else {
        plugin = x;
        optional = true;
      })
    lazy-plugins
    # bleeding-edge plugins from flake inputs
    ++ mapPlugins pkgs inputs "plugin:";

  extraPackages = with pkgs; [
    ripgrep
    fd
    fzf
  ];

	path = self;
in {
  # This is the neovim derivation
  # returned by the overlay
  nvim-pkg = mkNeovim {
    inherit path pkgs plugins extraPackages;
    ignoreConfigRegexes = ["^lua/packages.lua"];

    # Get rid of the import to `lua/packages.lua`
    trimLines = 2;
    extraLuaConfig =
      ../../lua/plugins
			|> readDir
      |> (filterAttrs (_name: value: value == "regular"))
      |> attrNames
        # Trim the ".lua" at the end
      |> (xs: map (x: substring 0 (stringLength x - 4) x) xs)
      |> (map (x: "require('plugins.${x}')"))
      |> (concatStringsSep "\n");
    # extraLuaConfig = fold
    # (curr: acc: concatStringsSep acc)
    # ""
    # (attrNames (filterAttrs (_name: value: value == "regular") (readDir ../../lua/plugins)))
    # ;

    # > ERROR: noBrokenSymlinks: the symlink /nix/store/72rpvpr77p7j23c5hkxai3cv3hkhvmzm-lldb-14.0.
    # 6-lib/lib/python3.12/site-packages/lldb/lldb-argdumper points to a missing target /nix/store/
    # 72rpvpr77p7j23c5hkxai3cv3hkhvmzm-lldb-14.0.6-lib/bin/lldb-argdumper
    #
    # > ERROR: noBrokenSymlinks: found 1 dangling symlinks and 0 reflexive symlinks
    # For full logs, run 'nix log /nix/store/ppjniqd4cnn4rl4zlgk6qixn0pzq8j8l-lldb-14.0.6.drv'
    # extraLuaConfig = let
    #   codelldb = pkgs.vscode-extensions.vadimcn.vscode-lldb;
    # in ''
    #   vim.g.codelldb_path = '${codelldb}/share/vscode/extensions/vadimcn.vscode-lldb/'
    # '';
  };

  # This can be symlinked in the devShell's shellHook
  # nvim-luarc-json = final.mk-luarc-json {
  #   plugins = plugins;
  # };

  # You can add as many derivations as you like.
  # Use `ignoreConfigRegexes` to filter out config
  # files you would not like to include.
  #
  # For example:
  #
  # nvim-pkg-no-telescope = mkNeovim {
  #   plugins = [];
  #   ignoreConfigRegexes = [
  #     "^plugin/telescope.lua"
  #     "^ftplugin/.*.lua"
  #   ];
  #   inherit extraPackages;
  # };
}
