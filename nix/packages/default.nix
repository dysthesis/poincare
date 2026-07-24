{
  self,
  pkgs,
  lib,
  neovimNightly ? null,
}: let
  poincare = pkgs.callPackage ./poincare {
    inherit
      pkgs
      lib
      self
      ;
  };
in
  {
    default = poincare;
    inherit poincare;
  }
  // pkgs.lib.optionalAttrs (neovimNightly != null) {
    # CI canary only (nightly job in flake-check.yml); not part of `checks`
    # so `nix flake check` never gates on a nightly Neovim build.
    poincare-nightly = poincare.override {neovim-unwrapped = neovimNightly;};
  }
