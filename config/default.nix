{
  # Import all your configuration modules here
  imports = [
    ./plugins
    ./colourschemes
    ./options
  ];
  permittedInsecurePackages = [
    "nix-2.16.2" # TODO Get rid of this later!
  ];
}
