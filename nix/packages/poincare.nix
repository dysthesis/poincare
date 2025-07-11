{
  self,
  symlinkJoin,
  neovim-unwrapped,
  makeWrapper,
  runCommandLocal,
  vimPlugins,
  lib,
  ...
}: let
  sources = import ./npins;
  npins = lib.mapAttrs (k: v: import sources.${k} {}) sources;
  packageName = "plugins";
  plugins = with vimPlugins; with npins; [telescope-nvim lackluster-nvim];
  packPath = runCommandLocal "packpath" {} ''
    mkdir -p $out/pack/${packageName}/{start,opt}
    ${
      lib.concatMapStringsSep
      "\n"
      (plugin: "ln -vsfT ${plugin} $out/pack/${packageName}/start/${lib.getName plugin}")
      plugins
    }
  '';
in
  symlinkJoin rec {
    name = "poincare";
    paths = [neovim-unwrapped];
    nativeBuildInputs = [makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/nvim \
        --add-flags "-u" \
        --add-flags "${self}/src/init.lua" \
        --add-flags "--cmd" \
        --add-flags "'set packpath^=${packPath} | set runtimepath^=${packPath}'" \
        --set-default NVIM_APPNAME ${name}
    '';
    passthru = {
      inherit packPath;
    };
    meta.mainProgram = "nvim";
  }
