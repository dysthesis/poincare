{pkgs, ...}: {
  projectRootFile = "flake.nix";
  programs = {
    alejandra.enable = true;
    mdformat.enable = true;
    deadnix.enable = true;
    stylua.enable = true;
    prettier = {
      enable = true;
      package = pkgs.prettier;
    };
    toml-sort.enable = true;
    shfmt = {
      enable = true;
      indent_size = 4;
    };
  };
}
