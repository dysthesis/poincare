{
  description = "Personal Neovim flake.";

  outputs = {self, ...} @ inputs: let
    inherit (inputs.nixpkgs) lib;
    supportedSystems = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];

    # Eval the treefmt modules from ./nix/formatting.nix
    treefmtEval = eachSystem (
      {pkgs, ...}:
        inputs.treefmt-nix.lib.evalModule pkgs ./nix/formatting.nix
    );

    eachSystem = f:
      lib.genAttrs supportedSystems (
        system:
          f {
            inherit system;
            pkgs = import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
              overlays = [inputs.neovim-nightly-overlay.overlays.default];
            };
          }
      );
  in {
    devShells = eachSystem (
      {
        pkgs,
        system,
        ...
      }:
        import ./nix/shell.nix {
          inherit pkgs self;
          treefmt = treefmtEval.${system};
        }
    );
    formatter = eachSystem ({system, ...}: treefmtEval.${system}.config.build.wrapper);
    packages = eachSystem ({pkgs, ...}: import ./nix/packages {inherit pkgs lib inputs;});
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Repositrory-wide formatting
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # More maintained grammar for Nix that also has pipe operators
    tree-sitter-nix.url = "github:numtide/tree-sitter-nix";
  };
}
