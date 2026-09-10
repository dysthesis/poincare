{
  # Used to find the project root
  projectRootFile = "flake.nix";
  programs = {
    alejandra.enable = true;
    black.enable = true;
    stylua = {
      enable = true;
      settings = {
        column_width = 80;
        indent_type = "Spaces";
        indent_width = 2;
      };
    };
  };
}
