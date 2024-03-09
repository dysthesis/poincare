{
  plugins.none-ls = {
    enable = true;
    enableLspFormat = true;
    updateInInsert = false;

    sources = {
      code_actions = {
        gitsigns.enable = true;
        statix.enable = true;
      };
      formatting = {
        alejandra = {
          enable = true;
        };
      };
    };
  };
}
