{
  description = "A flake of chaos.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    treefmt = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    gen-luarc = {
      url = "github:mrcjkb/nix-gen-luarc-json";
      inputs.flake-parts.follows = "flake-parts";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Add bleeding-edge plugins here.
    # They can be updated with `nix flake update` (make sure to commit the generated flake.lock)
    "plugin:lzn-auto-require" = {
      url = "github:horriblename/lzn-auto-require";
      flake = false;
    };
    "plugin:ultimate-autopair.nvim" = {
      url = "github:altermo/ultimate-autopair.nvim";
      flake = false;
    };
    "plugin-lazy:markview.nvim" = {
      url = "github:OXY2DEV/markview.nvim";
      flake = false;
    };
    "plugin-lazy:helpview.nvim" = {
      url = "github:OXY2DEV/helpview.nvim";
      flake = false;
    };
    "plugin-lazy:neo-tree.nvim" = {
      url = "github:nvim-neo-tree/neo-tree.nvim";
      flake = false;
    };
    "plugin-lazy:neogit" = {
      url = "github:NeogitOrg/neogit";
      flake = false;
    };
  };

  outputs = inputs @ {
    nixpkgs,
    flake-parts,
    ...
  }: let
    lib = import ./lib inputs.nixpkgs.lib;
  in
    flake-parts.lib.mkFlake {
      inherit inputs;
      specialArgs = {inherit lib;};
    } {
      systems = import inputs.systems;
      imports = [
        ./parts
        inputs.treefmt.flakeModule
      ];
    };
}
