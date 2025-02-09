# Poincare

This is a (WIP) Neovim flake that

- can be used as a regular Neovim configuration (by placing this in `~/.config/nvim/`),
- snappy, and
- is minimal, but not to a fault.

Here, _minimal_ is defined as a rough measure of the amount of feature provided per line of code.

Speed takes precedence over minimalism.

## As a regular configuration

When Nix is not used, [savq/paq-nvim](https://github.com/savq/paq-nvim) is used to automatically install plugins. It is extremely minimal, and does nothing else other than installing plugins.
