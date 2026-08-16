{
  pkgs,
  lib,
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
      plugin.overrideAttrs (old: {
        postPatch =
          (old.postPatch or "")
          + ''
            rm -f after/queries/lean/highlights.scm
          '';
      })
    else plugin);
in
  with pkgs.vimPlugins;
    [
      mini-pick
      mini-extra # For LSP-based pickers
      mini-surround
      mini-icons
      blink-cmp

      smart-splits-nvim
      ultimate-autopair-nvim
      conform-nvim
      nvim-lint

      nvim-dap-ui
      nvim-dap-virtual-text

      lean-nvim
      todo-comments-nvim
      zen-mode-nvim
      gitsigns-nvim
    ]
    ++ mkNpins npins
