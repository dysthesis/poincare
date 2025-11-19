{
  description = "poincare - neovim flake";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    crane.url = "github:ipetkov/crane";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };
    babel = {
      url = "github:dysthesis/babel";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    flake-parts,
    crane,
    nixpkgs,
    babel,
    advisory-db,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
      perSystem = {
        config,
        self,
        pkgs,
        system,
        ...
      }: let
        inherit (babel) mkLib;
        lib = mkLib nixpkgs;
        craneLib = crane.mkLib pkgs;
        # Common arguments can be set here to avoid repeating them later
        # NOTE: changes here will rebuild all dependency crates
        src = craneLib.cleanCargoSource ./.;
        commonArgs = {
          inherit src;
          strictDeps = true;

          buildInputs = pkgs.lib.optionals pkgs.stdenv.isDarwin [
            pkgs.libiconv
          ];
        };

        cargoArtifacts = craneLib.buildDepsOnly commonArgs;
      in rec {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [
            inputs.rust-overlay.overlays.default
          ];
        };
        checks = import ./nix/checks {
          inherit (packages) poincare;
          inherit (pkgs) lib;
          inherit
            craneLib
            cargoArtifacts
            commonArgs
            src
            advisory-db
            ;
        };

        packages = import ./nix/pkgs {
          inherit
            craneLib
            pkgs
            self
            lib
            crane
            inputs
            commonArgs
            cargoArtifacts
            ;
        };

        devShells.default = craneLib.devShell {
          inherit (config) checks;
          packages = with pkgs; [
            nixd
            statix
            deadnix
            nixfmt
            alejandra

            cargo-audit
            cargo-expand
            cargo-nextest
            bacon
            rust-analyzer
          ];
        };
      };
    };
}
