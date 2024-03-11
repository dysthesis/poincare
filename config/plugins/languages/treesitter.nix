{
  plugins = {
    treesitter = {
      enable = true;
      nixGrammars = true;
      indent = true;
      # folding = true;
      nixvimInjections = true;
    };
    treesitter-context.enable = true;

    treesitter-refactor = {
      enable = true;
      highlightDefinitions = {
        enable = true;
        clearOnCursorMove = true;
      };
      smartRename.enable = true;
      navigation.enable = true;
    };
  };
}
