{
  pkgs,
  self,
  treefmt,
  inputs,
  ...
}: let
  styluaOptions =
    treefmt.config.settings.formatter.stylua.options;

  styluaConfig = assert builtins.length styluaOptions == 2;
  assert builtins.elemAt styluaOptions 0 == "--config-path";
    builtins.elemAt styluaOptions 1;
in {
  default = pkgs.mkShellNoCC {
    MINI_TEST_RTP = pkgs.vimPlugins.mini-nvim;
    POINCARE_PACKPATH = self.packages.${pkgs.system}.poincare.packpath;
    TEST_NVIM = pkgs.neovim-unwrapped;
    TEST_BASH = pkgs.bash;
    TEST_CORE = pkgs.coreutils;
    TEST_UTIL =
      if pkgs.stdenv.hostPlatform.isLinux
      then pkgs.util-linux
      else "";
    TEST_IP =
      if pkgs.stdenv.hostPlatform.isLinux
      then pkgs.iproute2
      else "";
    TEST_NIX = pkgs.nix;
    TEST_PYTHON = pkgs.python3;
    TEST_SELENE = pkgs.selene;
    TEST_SQLITE = pkgs.sqlite;

    inputsFrom = [
      treefmt.config.build.devShell
    ];
    packages =
      (with pkgs; [
        # Build the plugin runtime and namespace tools for focused regressions.
        self.packages.${pkgs.system}.poincare.packpath
        bash
        coreutils
        nix
        python3

        # Lua development
        neovim
        stylua
        lua-language-server
        selene
        # Real Dadbod regression: inspect both physical database files.
        sqlite

        # Management for plugins outside of nixpkgs
        npins

        # Nix development
        nil
        statix
        deadnix
        alejandra
        nixfmt

        # Python for dev scripts
        (python3.withPackages (p: with p; [rich]))
        basedpyright
        black

        # Miscellaneous tooling
        just
        hyperfine

        inputs.bombadil.packages.${pkgs.system}.default
        cargo
        fish
      ])
      ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux (with pkgs; [
        util-linux
        iproute2
      ]);

    shellHook = ''
      root="$PWD"

      while [[ "$root" != "/" && ! -f "$root/flake.nix" ]]; do
        root="''${root%/*}"
        [[ -n "$root" ]] || root="/"
      done

      if [[ -f "$root/flake.nix" ]]; then
        ln -sfn ${styluaConfig} "$root/.stylua.toml"
      fi
    '';
  };
}
