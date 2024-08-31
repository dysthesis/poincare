lib:
lib.extend (_final: _prev: {
  nvim = {
    plugin = import ./plugin.nix _final;
    mkNeovim = import ./mkNeovim.nix;
  };
})
