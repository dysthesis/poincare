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

    # Repo sources for lint and test checks, minus VCS/build noise.
    luaSrcFor = pkgs:
      pkgs.lib.cleanSourceWith {
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

    vimChecksFor = import ./nix/checks.nix luaSrcFor;
  in
    # Budget flake-parts
    mapAttrs (_: forAllSystems) rec {
      devShells = pkgs: {
        default = import ./nix/shell pkgs (packages pkgs).poincare;
      };

      # for `nix fmt`
      formatter = pkgs: treefmt.${pkgs.stdenv.hostPlatform.system}.config.build.wrapper;
      # for `nix flake check`
      checks = pkgs: let
        inherit (pkgs.lib) attrByPath findFirst optionalString;

        luaSrc = luaSrcFor pkgs;

        mkLuaCheck = name: drv: configPath:
          pkgs.runCommand "check-${name}" {
            nativeBuildInputs = [drv pkgs.coreutils];
          } ''
            set -eu
            export HOME="$TMPDIR"
            cd ${luaSrc}
            ${drv}/bin/${name} ${optionalString (configPath != null)
              "--config ${configPath}"} .
            touch "$out"
          '';

        mkCheckIfAvailable = name: drv: configPath:
          if
            drv
            != null
            && pkgs.lib.meta.availableOn pkgs.stdenv.hostPlatform drv
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
      in
        {
          formatting = treefmt.${pkgs.stdenv.hostPlatform.system}.config.build.check self;
          selene = mkCheckIfAvailable "selene" pkgs.selene "${self}/selene.toml";
          luacheck = mkCheckIfAvailable "luacheck" luacheckDrv "${self}/.luacheckrc";
        }
        // vimChecksFor pkgs (packages pkgs).poincare;

      packages = pkgs: let
        base = import ./nix/packages {
          inherit pkgs lib self inputs;
          neovimNightly =
            inputs.neovim-nightly-overlay.packages.${pkgs.stdenv.hostPlatform.system}.default
            or null;
        };
      in
        base
        // {
          # every Neovim-level check built against the nightly package.
          poincare-nightly-checks =
            pkgs.linkFarm "poincare-nightly-checks"
            (vimChecksFor pkgs base.poincare-nightly);
        };
    };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # More maintained grammar for Nix that also has pipe operators
    tree-sitter-nix.url = "github:numtide/tree-sitter-nix";

    # Personal library
    nixpressions = {
      url = "github:dysthesis/nixpressions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # CI nightly canary. Its own pin matches nix-community.cachix.org; following
    # this flake's nixpkgs would force CI to compile Neovim HEAD.
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
  };
}
