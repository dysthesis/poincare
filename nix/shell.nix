{pkgs, ...}: {
  default = pkgs.mkShellNoCC {
    packages = with pkgs; [
      # Nix development
      nil
      statix
      deadnix
      alejandra
    ];
  };
}
