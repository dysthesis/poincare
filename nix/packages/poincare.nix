{
  self,
  symlinkJoin,
  neovim-unwrapped,
  makeWrapper,
  runCommand,
  runCommandLocal,
  vimPlugins,
  vimUtils,
  lib,
  ...
}:
let
  sources = import ./npins;
  npins = lib.mapAttrs (k: _v: import sources.${k} { }) sources;
  packageName = "plugins";

  config = vimUtils.buildVimPlugin {
    name = "poincare";
    src = runCommand "poincare-config-src" { } ''
      mkdir -p $out/plugin
      cp -r ${self}/src/init.lua $out/plugin/
      cp -r ${self}/src/lua $out/
    '';
    doCheck = false;
  };

  plugins =
    with vimPlugins;
    with npins;
    [
      config
      (nvim-treesitter.withPlugins (
        p: with p; [
          go
          bash
          fish
          diff
          dockerfile
          asm
          disassembly
          git_config
          git_rebase
          gitignore
          python
          zig
          rust
          haskell
          nix
          lua
          toml
          yaml
          markdown
          latex
          typst
        ]
      ))
      lackluster-nvim
    ];
  packPath = runCommandLocal "packpath" { } ''
    mkdir -p $out/pack/${packageName}/{start,opt}
    ${lib.concatMapStringsSep "\n" (
      plugin: "ln -vsfT ${plugin} $out/pack/${packageName}/start/${lib.getName plugin}"
    ) plugins}
  '';
in
symlinkJoin rec {
  name = "poincare";
  paths = [ neovim-unwrapped ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/nvim \
      --add-flags "-u" \
      --add-flags "NORC" \
      --add-flags "--cmd" \
      --add-flags "'set packpath^=${packPath} | set runtimepath^=${packPath}'" \
      --set-default NVIM_APPNAME ${name}
  '';
  passthru = {
    inherit packPath;
  };
  meta.mainProgram = "nvim";
}
