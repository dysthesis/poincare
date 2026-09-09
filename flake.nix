{
  description = "Personal Neovim flake.";

  outputs = {self, ...} @ inputs: let
    inherit (inputs.nixpkgs) lib;

    supportedSystems = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];

    # Eval the treefmt modules from ./treefmt.nix
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
    devShells = eachSystem (import ./nix/shell.nix);
    formatter = eachSystem (pkgs: treefmtEval.${pkgs.system}.config.build.wrapper);
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
