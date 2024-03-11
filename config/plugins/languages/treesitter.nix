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
  };
}
