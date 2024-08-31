# Hacks

This lists some hacks that I have employed to get things working.

## CodeLLDB

Instead of wrapping my Lua configs in Nix to interpolate the path of CodeLLDB into it, I added a line in the build process in `mkNeovim` to prepend some Lua code that defines a global variable that stores where CodeLLDB is in the Nix store.
