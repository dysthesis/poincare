{
  plugins.none-ls = {
    enable = true;
    enableLspFormat = false;
    updateInInsert = false;

    diagnosticConfig = {
      statix = {
        enable = true;
      };
      deadnix.enable = true;
      gitlint.enable = true;
      luacheck = {
        enable = true;
      };
    };

    sources = {
      code_actions = {
        gitsigns.enable = true;
        statix.enable = true;
      };

      diagnostics = {
        checkstyle.enable = true;
        statix.enable = true;
        luacheck.enable = true;
      };

      formatting = {
        alejandra = {
          enable = true;
        };
        rustfmt.enable = true;
      };
    };
  };
}
