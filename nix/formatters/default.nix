_: {
  projectRootFile = "flake.nix";
  programs = {
    nixfmt.enable = true;
    mdformat.enable = true;
    deadnix.enable = true;
    stylua.enable = true;
    prettier.enable = true;
    toml-sort.enable = true;
    fnlfmt.enable = true;
    shfmt = {
      enable = true;
      indent_size = 4;
    };
  };
}
