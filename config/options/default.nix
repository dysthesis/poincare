{
  config.options = {
    autoindent = true;
    cursorline = true;
    tabstop = 2;
    shiftwidth = 2;
    linebreak = true;
    mouse = "";
    number = true;
    relativenumber = true;
  };
  imports = [
    ./keybinds.nix
  ];
}
