{
  pkgs,
  treefmt,
  ...
}: let
  styluaOptions =
    treefmt.config.settings.formatter.stylua.options;

  styluaConfig = assert builtins.length styluaOptions == 2;
  assert builtins.elemAt styluaOptions 0 == "--config-path";
    builtins.elemAt styluaOptions 1;
in {
  default = pkgs.mkShellNoCC {
    inputsFrom = [
      treefmt.config.build.devShell
    ];
    packages = with pkgs; [
      # Lua development
      stylua
      lua-language-server
      selene

      # Management for plugins outside of nixpkgs
      npins

      # Nix development
      nil
      statix
      deadnix
      alejandra

      # Python for dev scripts
      (python3.withPackages (p: with p; [rich]))
      basedpyright
      black

      # Miscellaneous tooling
      just
    ];

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
