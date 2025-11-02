# Fennel

Fennel is dialect of Lisp that compiles to Lua. Neovim can be configured with Fennel, though not natively.

## Nix

Given that this configuration is packaged as a Nix flake, Fennel can be compiled to Lua in the derivation.

The advantage of this is that it prevents unnecessary dependencies. There is no need to install any additional plugins.

## Aniseed

[Aniseed](https://github.com/Olical/aniseed)
