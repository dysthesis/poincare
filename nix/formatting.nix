{
  # Used to find the project root
  projectRootFile = "flake.nix";
  programs = {
    alejandra.enable = true;
    stylua = {
      enable = true;
      settings = {
        column_width = 80;
        indent_type = "Spaces";
      };
    };
  };
}
