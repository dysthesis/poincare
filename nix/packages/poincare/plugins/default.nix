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
      mini-ai # More (a)round/(i)nside motions
      mini-clue # Cheatsheet for keybindings
      mini-indentscope # Visualise indentations
      mini-surround # Motions to manipulate surrounding delimiters
      smart-splits-nvim # Unified split management binding with tmux
      vim-tmux-navigator # Unified navigation binding with tmux
      blink-cmp # Fast completion
      luasnip # Snippet engine
      friendly-snippets # Community snippet collection
      ultimate-autopair-nvim # Smarter autopairs that recognises more patterns
      conform-nvim # Asynchronous, automatic formatting
      inc-rename-nvim # LSP symbol renaming
      oil-nvim # Edit directories as text buffers
      harpoon2 # Quick bookmarks
      zen-mode-nvim # More focused view
      twilight-nvim # Dim text for zen-mode-nvim
      gitsigns-nvim # Display git deltas on editor
      nvim-lint # Lint diagnostics
      flash-nvim # Quick jumps
      todo-comments-nvim # Highlight and navigate TOOD comments
      inputs.tachyon.packages.${pkgs.system}.default # Custom fuzzy matcher
      zk-nvim # Note-taking

      # Language support
      rustaceanvim # Rust support
      lean-nvim # Lean theorem prover
      inputs.rustowl.packages.${pkgs.system}.rustowl-nvim # Rust lifetimes
    ]
    ++ builtNpins
    ++ mapPlugins pkgs inputs "plugin-lazy"
