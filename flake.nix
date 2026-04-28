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
      formatter = pkgs: treefmt.${pkgs.stdenv.hostPlatform.system}.config.build.wrapper;
      # for `nix flake check`
      checks = pkgs: let
        inherit (pkgs.lib) attrByPath findFirst optionalString;
        inherit (packages pkgs) poincare;

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

        runtime = pkgs.runCommand "check-poincare-runtime" {nativeBuildInputs = [pkgs.coreutils];} ''
          set -eu

          mkdir -p "$TMPDIR/home"
          cat > "$TMPDIR/runtime-check.lua" <<'LUA'
          local function fail(message)
            error(message, 0)
          end

          local function expect_executable(name)
            if vim.fn.executable(name) ~= 1 then
              fail(name .. ' is not executable')
            end
          end

          expect_executable('rg')
          expect_executable('fd')
          expect_executable('tree-sitter')

          if vim.fn.executable(vim.env.CODELLDB_PATH or "") ~= 1 then
            fail('CODELLDB_PATH is not executable')
          end

          local dap_continue = vim.fn.maparg(' Dc', 'n', false, true)
          if dap_continue.desc ~= 'Continue' then
            fail('<leader>Dc should remain DAP continue, got ' .. vim.inspect(dap_continue.desc))
          end

          local dap_close = vim.fn.maparg(' Dx', 'n', false, true)
          if dap_close.desc ~= '[D]ebug Close UI' then
            fail('<leader>Dx should close DAP UI, got ' .. vim.inspect(dap_close.desc))
          end
          LUA

          env -i \
            HOME="$TMPDIR/home" \
            PATH="${pkgs.coreutils}/bin" \
            ${poincare}/bin/nvim --headless "+luafile $TMPDIR/runtime-check.lua" +qa

          touch "$out"
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
        formatting = treefmt.${pkgs.stdenv.hostPlatform.system}.config.build.check self;
        selene = mkCheckIfAvailable "selene" pkgs.selene "${self}/selene.toml";
        luacheck = mkCheckIfAvailable "luacheck" luacheckDrv "${self}/.luacheckrc";
        inherit runtime;
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

    # Personal library
    nixpressions = {
      url = "github:dysthesis/nixpressions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
