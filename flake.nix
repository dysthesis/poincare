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

    # lz-n v2.0.0 onwards breaks the loading of some plugins, namely
    # - telescope,
    # - neogit, and
    # - neotree,
    # so we pin it to the latest working version for now.
    "plugin:lz-n".url = "github:nvim-neorocks/lz.n/v1.4.4";
    "plugin:lzn-auto-require" = {
      url = "github:horriblename/lzn-auto-require";
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
    "plugin:ultimate-autopair.nvim" = {
      url = "github:altermo/ultimate-autopair.nvim";
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
