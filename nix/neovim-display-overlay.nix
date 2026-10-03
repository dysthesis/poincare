# Native display lifecycle fixes for the pinned d039f19 Neovim runtime.
final: prev: {
  neovim-unwrapped = prev.neovim-unwrapped.overrideAttrs (old: {
    patches = (old.patches or []) ++ [./neovim-display.patch];
  });
  # The nightly overlay exposes neovim as an alias, not a wrapper.
  neovim = final.neovim-unwrapped;
}
