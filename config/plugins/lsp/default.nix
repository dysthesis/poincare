{pkgs, ...}: {
  plugins.lsp = {
    enable = true;
    servers = {
      nil_ls.enable = true;
      nixd = {
        enable = true;
        formatting.command = "${pkgs.alejandra}/bin/alejandra";
      };
    };
  };

  imports = [
    ./lsp-format.nix
  ];
}
