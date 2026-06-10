{
  pkgs,
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
    mkNvimPlugin
    ;

  # npins adds a __functor attribute for backward compatibility; drop it so
  # we only iterate actual pins when building plugin derivations.
  npins = removeAttrs (import ./npins) ["__functor"];
  mkNpins = mapAttrsToList (pname: src: let
    plugin = mkNvimPlugin {
      inherit pkgs src pname;
      version = src.revision;
    };
  in
    if pname == "minimal.nvim"
    then
      # The pinned Julian/tree-sitter-lean grammar no longer exposes the node
      # shapes minimal.nvim's lean after-queries expect, and the ';; extends'
      # file poisons every lean highlights compile ("Impossible pattern"),
      # killing lean treesitter highlighting outright. Drop it; base
      # highlights come from nvim-treesitter-lean.
      plugin.overrideAttrs (old: {
        postPatch =
          (old.postPatch or "")
          + ''
            rm -f after/queries/lean/highlights.scm
          '';
      })
    else plugin);
  builtNpins = mkNpins npins;
in
  with pkgs.vimPlugins;
    [
      mini-pick
      mini-extra # For LSP-based pickers
      mini-surround
      mini-icons
      mini-test # Harness for the behavioural suite (tests/)
      blink-cmp
      blink-compat

      smart-splits-nvim
      ultimate-autopair-nvim
      conform-nvim
      nvim-lint

      # Debugging
      nvim-nio
      nvim-dap
      nvim-dap-ui
      nvim-dap-virtual-text

      lean-nvim
      plenary-nvim
      gitsigns-nvim

      # Language-specific
      clangd_extensions-nvim
    ]
    ++ builtNpins
