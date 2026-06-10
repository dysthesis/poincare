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

          vim.cmd.packadd('lean.nvim')
          if #vim.api.nvim_get_runtime_file('queries/lean/highlights.scm', true) == 0 then
            fail('Lean treesitter queries are not on runtimepath')
          end
          if #vim.api.nvim_get_runtime_file('queries/lean/indents.scm', true) == 0 then
            fail('Lean treesitter parser queries are not on runtimepath')
          end
          local query_files = vim.treesitter.query.get_files('lean', 'highlights')
          if not query_files[1] or not query_files[1]:find('nvim%-treesitter%-lean', 1) then
            fail('Lean treesitter parser queries do not take precedence: ' .. vim.inspect(query_files))
          end
          local queries_ok, query_err = pcall(vim.treesitter.query.get, 'lean', 'highlights')
          if not queries_ok then
            fail('Lean treesitter highlight queries failed: ' .. tostring(query_err))
          end
          if #vim.api.nvim_get_runtime_file('parser/lean.*', true) == 0 then
            fail('Lean treesitter parser is not on runtimepath')
          end

          vim.cmd.enew()
          vim.bo.filetype = 'lean'
          local ok, err = pcall(vim.treesitter.start, 0, 'lean')
          if not ok then
            fail('Lean treesitter parser failed: ' .. tostring(err))
          end

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

        # Headless boot must write nothing to stderr and exit zero. This
        # catches the entire class of lz.n spec/handler/keymap errors that
        # print on every boot but never fail loudly.
        boot-purity = pkgs.runCommand "check-poincare-boot-purity" {nativeBuildInputs = [pkgs.coreutils];} ''
          set -eu

          mkdir -p "$TMPDIR/home"
          rc=0
          env -i \
            HOME="$TMPDIR/home" \
            PATH="${pkgs.coreutils}/bin" \
            ${poincare}/bin/nvim --headless +qa 2>"$TMPDIR/stderr.log" || rc=$?

          if [ "$rc" -ne 0 ] || [ -s "$TMPDIR/stderr.log" ]; then
            echo "headless boot failed (exit $rc) or wrote to stderr:" >&2
            cat "$TMPDIR/stderr.log" >&2
            exit 1
          fi

          touch "$out"
        '';

        # Expected checkhealth ERROR lines (fixed-string match, one per line;
        # no blank lines — an empty pattern would match everything):
        #   - tar/curl: external tools intentionally absent from the closure
        #     (README policy: runtime tools come from the environment).
        #   - "is not in runtimepath": nvim-treesitter's download/install dir
        #     ($XDG_DATA_HOME/poincare/site) — unused; parsers ship via Nix.
        #   - locale: hermetic env has no locale archive on some platforms
        #     even with LANG=C.UTF-8 set below; not a property of the config.
        checkhealthAllowlist = pkgs.writeText "checkhealth-allowlist" ''
          tar not found
          curl not found
          is not in runtimepath
          Locale does not support UTF-8
        '';

        checkhealth = pkgs.runCommand "check-poincare-checkhealth" {nativeBuildInputs = [pkgs.coreutils];} ''
          set -eu

          mkdir -p "$TMPDIR/home"
          env -i \
            HOME="$TMPDIR/home" \
            LANG=C.UTF-8 \
            PATH="${pkgs.coreutils}/bin" \
            ${poincare}/bin/nvim --headless \
              "+silent! checkhealth" \
              "+silent! write! $TMPDIR/health.txt" \
              +qa 2>/dev/null

          test -s "$TMPDIR/health.txt"

          if grep ERROR "$TMPDIR/health.txt" | grep -v -F -f ${checkhealthAllowlist} > "$TMPDIR/unexpected.txt"; then
            echo "checkhealth reported non-allowlisted ERRORs:" >&2
            cat "$TMPDIR/unexpected.txt" >&2
            exit 1
          fi

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
        inherit runtime boot-purity checkhealth;
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
