pkgs:
pkgs.mkShell {
  name = "Poincare";
  packages = with pkgs; [
    nil
    alejandra
    statix
    deadnix
    lua-language-server
    stylua
  ];

  shellHook =
    /*
    sh
    */
    ''
      # Symlink the .luarc.json generated in the overlay
      ln -fs ${pkgs.nvim-luarc-json} .luarc.json
    '';
}
