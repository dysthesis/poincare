{
  description = "A flake of chaos.";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Personal library
    babel = {
      url = "github:dysthesis/babel";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Get plugins directly from git
    "plugin-lazy:lackluster.nvim" = {
      url = "github:slugbyte/lackluster.nvim";
      flake = false;
    };
    blink-cmp = {
      url = "github:Saghen/blink.cmp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      babel,
      nixpkgs,
      treefmt-nix,
      ...
    }:
    let
      inherit (builtins) mapAttrs;
      inherit (babel) mkLib;
      lib = mkLib nixpkgs;

      # Systems to support
      systems = [
        "aarch64-linux"
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = lib.babel.forAllSystems { inherit systems; };

      treefmt = forAllSystems (pkgs: treefmt-nix.lib.evalModule pkgs ./nix/formatters);
    in
    # Budget flake-parts
    mapAttrs (_: val: forAllSystems val) {
      devShells = pkgs: { default = import ./nix/shell pkgs; };
      # for `nix fmt`
      formatter = pkgs: treefmt.${pkgs.system}.config.build.wrapper;
      # for `nix flake check`
      checks = pkgs: {
        formatting = treefmt.${pkgs.system}.config.build.check self;
      };
      packages =
        pkgs:
        import ./nix/packages {
          inherit
            inputs
            pkgs
            lib
            self
            ;
        };
    };
}
