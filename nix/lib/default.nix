inputs:
inputs.nixpkgs.lib.extend (_final: _prev: {
  poincare = {
    forAllSystems = import ./forAllSystems.nix inputs.nixpkgs;
    mkNeovim = import ./mkNeovim.nix;
    mkPlugin = import ./mkPlugin.nix _final;
  };
})
