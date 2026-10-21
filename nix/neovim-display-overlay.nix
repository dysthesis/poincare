# Native display lifecycle and root-startup fixes for pinned d039f19 Neovim.
final: prev: {
  neovim-unwrapped = prev.neovim-unwrapped.overrideAttrs (old: {
    patches = (old.patches or []) ++ [./neovim-display.patch ./neovim-root.patch];
  });
  # The nightly overlay exposes neovim as an alias, not a wrapper.
  neovim = final.neovim-unwrapped;
}
