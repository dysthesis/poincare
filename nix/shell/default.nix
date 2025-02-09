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
}
