{
  pkgs,
  inputs,
  lib,
  ...
}: let
  inherit (lib) mapAttrsToList;
  inherit (lib.attrsets) removeAttrs;
  inherit (builtins) isAttrs;

  inherit
    (lib.babel.nvim)
    mapPlugins
    mkNvimPlugin
    ;

  npins = import ./npins;
  zigLampSrc = npins."zig-lamp";

  mkNpins = mapAttrsToList (pname: src:
    mkNvimPlugin {
      inherit pkgs src pname;
      version = src.revision;
    });
  zigLampVersion = zigLampSrc.version or zigLampSrc.revision;
  zigLampPlugin =
    (pkgs.vimUtils.buildVimPlugin {
      pname = "zig-lamp";
      version = zigLampVersion;
      src = zigLampSrc;
      dependencies = [
        pkgs.vimPlugins.plenary-nvim
      ];
    })
    .overrideAttrs (
      final: prev: {
        nativeBuildInputs = (prev.nativeBuildInputs or []) ++ [pkgs.zig];
        buildPhase = ''
          runHook preBuild
          export HOME="$TMPDIR"
          export ZIG_CACHE_DIR="$TMPDIR/zig-cache"
          export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
          mkdir -p "$ZIG_CACHE_DIR" "$ZIG_GLOBAL_CACHE_DIR"
          zig build \
            --cache-dir "$ZIG_CACHE_DIR" \
            --global-cache-dir "$ZIG_GLOBAL_CACHE_DIR"
          runHook postBuild
        '';
      }
    );
  builtNpins =
    mkNpins (removeAttrs npins ["zig-lamp"])
    ++ [
      zigLampPlugin
    ];

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
      trouble-nvim

      lean-nvim
      plenary-nvim

      nvim-dap
      nvim-dap-ui
      nvim-dap-virtual-text
      nvim-dap-go
      nvim-nio
      fidget-nvim

      # markview-nvim

      friendly-snippets

      conform-nvim

      todo-comments-nvim
      harpoon2

      inc-rename-nvim

      # Rust
      rustaceanvim
      crates-nvim

      # LaTeX
      vimtex
      nabla-nvim

      # Typst
      typst-preview-nvim

      # Notetaking
      zk-nvim

      # Navigation
      leap-nvim
      mini-surround
      mini-icons
      mini-ai
      mini-indentscope
      mini-clue

      fzf-lua

      zen-mode-nvim
      twilight-nvim

      lz-n

      diffview-nvim
      gitsigns-nvim
      git-conflict-nvim

      oil-nvim
      ultimate-autopair-nvim
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
      nvim-treesitter-textobjects # https://github.com/nvim-treesitter/nvim-treesitter-textobjects/
      smart-splits-nvim
      nvim-lint
      neoscroll-nvim
      neotest
      blink-cmp
      blink-compat
      neogen
    ]
    ++ builtNpins
    ++ mapPlugins pkgs inputs "plugin-lazy";

  plugins =
    map (
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
