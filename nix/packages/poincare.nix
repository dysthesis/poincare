{
  self,
  inputs,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib.babel.nvim) mkNeovim;
  inherit (builtins)
    readDir
    attrNames
    concatStringsSep
    stringLength
    substring
    ;

  inherit (lib) filterAttrs;

  plugins = import ./plugins { inherit pkgs inputs lib; };
  extraPackages = with pkgs; [
    ripgrep
    fd
    uutils-coreutils-noprefix
    tree-sitter
    nodejs
  ];

  path = self;
in
mkNeovim {
  inherit
    path
    pkgs
    plugins
    extraPackages
    ;
  ignoreConfigRegexes = [ "^lua/packages.lua" ];
  extraLuaPackages = p: with p; [ lyaml ];

  # Get rid of the import to `lua/packages.lua`
  trimLines = 2;
  extraLuaConfig =
    let
      codelldb = pkgs.vscode-extensions.vadimcn.vscode-lldb;
      loadPlugins =
        ../../lua/plugins
        |> readDir
        |> (filterAttrs (_name: value: value == "regular"))
        |> attrNames
        # Trim the ".lua" at the end
        |> (xs: map (x: substring 0 (stringLength x - 4) x) xs)
        |> (map (x: "require('plugins.${x}')"))
        |> (concatStringsSep "\n");
    in
    # lua
    ''
      vim.g.codelldb_path = '${codelldb}/share/vscode/extensions/vadimcn.vscode-lldb/adapter/codelldb'
      vim.g.liblldb_path = '${codelldb}/share/vscode/extensions/vadimcn.vscode-lldb/lldb/lib/liblldb.so'
      vim.g.isabelle_path = '${lib.getExe pkgs.isabelle}'
      ${loadPlugins}
    '';
}
