lib:
lib.extend (final: prev: {
  nvim = {
    plugin = import ./plugin.nix lib;
  };
})
