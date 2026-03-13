{
  description = "A flake of chaos.";

  outputs = inputs @ {
    self,
    nixpressions,
    nixpkgs,
    treefmt-nix,
    ...
  }: let
    inherit (builtins) mapAttrs;
    inherit (nixpressions) mkLib;
    lib = mkLib nixpkgs;

    # Systems to support
    systems = [
      "aarch64-linux"
      "x86_64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    forAllSystems = lib.babel.forAllSystems {inherit systems;};

    treefmt =
      forAllSystems
      (pkgs: treefmt-nix.lib.evalModule pkgs ./nix/formatters);
  in
    # Budget flake-parts
    mapAttrs (_: forAllSystems) rec {
      devShells = pkgs: {
        default = import ./nix/shell pkgs (packages pkgs).poincare;
      };

      # for `nix fmt`
      formatter = pkgs: treefmt.${pkgs.system}.config.build.wrapper;
      # for `nix flake check`
      checks = pkgs: let
        inherit (pkgs.lib) attrByPath findFirst optionalString;

        luaSrc = pkgs.lib.cleanSourceWith {
          src = self;
          filter = path: _type: let
            base = baseNameOf path;
          in
            !(base
              == ".git"
              || base == ".jj"
              || base == ".direnv"
              || base == "nix"
              || base == "result"
              || base == "results"
              || base == "dist"
              || base == "target");
        };

        mkLuaCheck = name: drv: configPath:
          pkgs.runCommand "check-${name}" {
            nativeBuildInputs = [drv pkgs.coreutils];
          } ''
            set -eu
            export HOME="$TMPDIR"
            cd ${luaSrc}
            ${drv}/bin/${name} ${optionalString (configPath != null) "--config ${configPath}"} .
            touch "$out"
          '';

        mkCheckIfAvailable = name: drv: configPath:
          if drv != null && pkgs.lib.meta.availableOn pkgs.stdenv.hostPlatform drv
          then mkLuaCheck name drv configPath
          else
            pkgs.runCommand "skip-${name}" {} ''
              echo "${name} unavailable on ${pkgs.stdenv.hostPlatform.system}" > "$out"
            '';

        luacheckDrv = findFirst (x: x != null) null (map (p: attrByPath p null pkgs) [
          ["luacheck"]
          ["luaPackages" "luacheck"]
          ["lua54Packages" "luacheck"]
          ["lua53Packages" "luacheck"]
          ["lua52Packages" "luacheck"]
          ["lua51Packages" "luacheck"]
        ]);
      in {
        formatting = treefmt.${pkgs.system}.config.build.check self;
        selene = mkCheckIfAvailable "selene" pkgs.selene "${self}/selene.toml";
        luacheck = mkCheckIfAvailable "luacheck" luacheckDrv "${self}/.luacheckrc";
      };
      packages = pkgs:
        import ./nix/packages {
          inherit
            inputs
            pkgs
            lib
            self
            ;
        };
    };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rustowl = {
      url = "github:nix-community/rustowl-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tachyon = {
      url = "github:dysthesis/tachyon";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Personal library
    nixpressions = {
      url = "github:dysthesis/nixpressions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
