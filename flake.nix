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
    treefmtEval =
      eachSystem
      ({pkgs, ...}:
        inputs.treefmt-nix.lib.evalModule pkgs ./nix/formatting.nix);

    eachSystem = f:
      lib.genAttrs supportedSystems (
        system:
          f {
            inherit system;
            pkgs = import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
          }
      );
  in {
    devShells = eachSystem ({
      pkgs,
      system,
      ...
    }:
      import ./nix/shell.nix {
        inherit pkgs;
        treefmt = treefmtEval.${system};
      });
    formatter = eachSystem ({system, ...}: treefmtEval.${system}.config.build.wrapper);
    packages = eachSystem ({pkgs, ...}: import ./nix/packages {inherit pkgs lib;});
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Repositrory-wide formatting
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
