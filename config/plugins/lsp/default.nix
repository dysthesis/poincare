{pkgs, ...}: {
  plugins.lsp = {
    enable = true;
    servers = {
      nil_ls.enable = true;
      nixd = {
        enable = true;
        settings.formatting.command = "${pkgs.alejandra}/bin/alejandra";
      };
    };
  };

  imports = [
    ./lsp-format.nix
  ];
}
