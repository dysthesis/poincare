{
  plugins.none-ls = {
    enable = true;
    enableLspFormat = true;
    updateInInsert = false;

    diagnosticConfig = {
      statix = {
        enable = true;
      };
      luacheck = {
        enable = true;
      };
    };

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
