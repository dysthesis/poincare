# Poincare

This is my personal Neovim flake. The configuration is written in Fennel, and
compiled into Lua during the Nix build process. Hence, there is no need for 
plugins which provide runtime support for Fennel.

- `fnl/lib/` providess nice abstractions for configuring Neovim. Basically all
  of it has been taken from [hibiscus-nvim]. Since Fennel is translated into
  Lua at runtime, we must vendor it ourselves instead of pulling it as a plugin.
  It also provides us with the flexibility of modifying it if we need to.

[hibiscus-nvim]: https://github.com/udayvir-singh/hibiscus.nvim
