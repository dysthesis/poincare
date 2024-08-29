lib:
lib.extend (_final: _prev: {
  nvim = {
    plugin = import ./plugin.nix lib;
  };
})
