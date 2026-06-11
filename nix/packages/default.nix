{
  self,
  pkgs,
  lib,
  inputs,
  ...
}: rec {
  default = poincare;
  poincare = pkgs.callPackage ./poincare {
    inherit
      pkgs
      inputs
      lib
      self
      ;
  };
  # Same wrapper and plugin set on nightly Neovim — the CI canary arm.
  # flake.nix builds the Neovim-level checks against it as
  # packages.poincare-nightly-checks (continue-on-error, never a gate).
  poincare-nightly = pkgs.callPackage ./poincare {
    inherit
      pkgs
      inputs
      lib
      self
      ;
    neovim-unwrapped = inputs.neovim-nightly-overlay.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };
}
