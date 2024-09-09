{
  perSystem = {pkgs, ...}: {
    devShells.default = pkgs.mkShell {
      name = "Poincare devshell";
      packages = with pkgs; [
        nil
        alejandra
        statix
        deadnix
      ];
      shellHook =
        /*
        sh
        */
        ''
          # Symlink the .luarc.json generated in the overlay
          ln -fs ${pkgs.nvim-luarc-json} .luarc.json
        '';
    };
  };
}
