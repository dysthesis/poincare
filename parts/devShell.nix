{
  perSystem = {pkgs, ...}: {
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        nil
        alejandra
        statix
        deadnix
      ];
    };
  };
}
