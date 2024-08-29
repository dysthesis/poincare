# This overlay, when applied to nixpkgs, adds the final neovim derivation to nixpkgs.
{
  inputs,
  lib,
}: final: prev:
with final.pkgs.lib; let
  inherit (lib.nvim.plugin) fromInputs;
  inherit (lib.attrsets) attrNames;
  pkgs = final;
  mapPlugins = prefix:
    map
    (x: mkNvimPlugin inputs."${prefix}${x}" x)
    (attrNames
      (fromInputs {
        inherit inputs prefix;
      }));

  # Use this to create a plugin from a flake input
  mkNvimPlugin = src: pname:
    pkgs.vimUtils.buildVimPlugin {
      inherit pname src;
      version = src.lastModifiedDate;
    };

  # Make sure we use the pinned nixpkgs instance for wrapNeovimUnstable,
  # otherwise it could have an incompatible signature when applying this overlay.
  pkgs-wrapNeovim = inputs.nixpkgs.legacyPackages.${pkgs.system};

  # This is the helper function that builds the Neovim derivation.
  mkNeovim = pkgs.callPackage ./mkNeovim.nix {inherit pkgs-wrapNeovim;};

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
      telescope-nvim
      telescope-fzf-native-nvim
      telescope-ui-select-nvim
      flash-nvim
      zen-mode-nvim
      twilight-nvim
      actions-preview-nvim
      zk-nvim
      comment-nvim
      nvim-surround
      neogit

      inc-rename-nvim
      undotree
      neo-tree-nvim
      neodev-nvim
      todo-comments-nvim
      nvim-lint

      noice-nvim
      luasnip # snippets | https://github.com/l3mon4d3/luasnip/

      # nvim-cmp (autocompletion) and extensions
      nvim-cmp # https://github.com/hrsh7th/nvim-cmp
      cmp_luasnip # snippets autocompletion extension for nvim-cmp | https://github.com/saadparwaiz1/cmp_luasnip/
      lspkind-nvim # vscode-like LSP pictograms | https://github.com/onsails/lspkind.nvim/
      cmp-nvim-lsp # LSP as completion source | https://github.com/hrsh7th/cmp-nvim-lsp/
      cmp-nvim-lsp-signature-help # https://github.com/hrsh7th/cmp-nvim-lsp-signature-help/
      cmp-buffer # current buffer as completion source | https://github.com/hrsh7th/cmp-buffer/
      cmp-path # file paths as completion source | https://github.com/hrsh7th/cmp-path/
      cmp-nvim-lua # neovim lua API as completion source | https://github.com/hrsh7th/cmp-nvim-lua/
      cmp-cmdline # cmp command line suggestions
      cmp-cmdline-history # cmp command line history suggestions
      # ^ nvim-cmp extensions
      nvim-lspconfig
      lspsaga-nvim
      friendly-snippets

      vim-tmux-navigator

      lualine-nvim
      conform-nvim
    ]
    ++ mapPlugins "plugin-lazy";

  all-plugins = with pkgs.vimPlugins;
    [
      nvim-treesitter.withAllGrammars

      # git integration plugins
      diffview-nvim # https://github.com/sindrets/diffview.nvim/
      gitsigns-nvim # https://github.com/lewis6991/gitsigns.nvim/
      # ^ git integration plugins

      # telescope and extensions
      # telescope-smart-history-nvim # https://github.com/nvim-telescope/telescope-smart-history.nvim
      # ^ telescope and extensions

      # UI
      statuscol-nvim # Status column | https://github.com/luukvbaal/statuscol.nvim/
      nvim-treesitter-context # nvim-treesitter-context
      # ^ UI

      # language support
      # ^ language support

      # navigation/editing enhancement plugins
      # vim-unimpaired # predefined ] and [ navigation keymaps | https://github.com/tpope/vim-unimpaired/
      # eyeliner-nvim # Highlights unique characters for f/F and t/T motions | https://github.com/jinh0/eyeliner.nvim
      # nvim-surround # https://github.com/kylechui/nvim-surround/
      nvim-treesitter-textobjects # https://github.com/nvim-treesitter/nvim-treesitter-textobjects/
      nvim-ts-context-commentstring # https://github.com/joosepalviste/nvim-ts-context-commentstring/
      # ^ navigation/editing enhancement plugins

      # Useful utilities
      nvim-unception # Prevent nested neovim sessions | nvim-unception
      # ^ Useful utilities

      # libraries that other plugins depend on
      sqlite-lua
      plenary-nvim
      nvim-web-devicons
      nui-nvim

      # ^ libraries that other plugins depend on

      # (mkNvimPlugin inputs.wf-nvim "wf.nvim") # (example) keymap hints | https://github.com/Cassin01/wf.nvim
      which-key-nvim

      # Colourscheme
      catppuccin-nvim

      # Lazy loading
      lz-n
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
    ++ mapPlugins "plugin:";

  extraPackages = with pkgs; [
    # language servers, etc.
    lua-language-server
    stylua
    nil # nix LSP
    zk
  ];
in {
  # This is the neovim derivation
  # returned by the overlay
  nvim-pkg = mkNeovim {
    plugins = all-plugins;
    inherit extraPackages;
  };

  # This can be symlinked in the devShell's shellHook
  nvim-luarc-json = final.mk-luarc-json {
    plugins = all-plugins;
  };

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
