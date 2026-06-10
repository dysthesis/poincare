{
  symlinkJoin,
  neovim-unwrapped,
  makeWrapper,
  runCommandLocal,
  lib,
  name,
  startPlugins,
  optPlugins,
  configDir,
  extraPackages,
  extraWrapperArgs ? [],
  extraPassthru,
  meta,
}: let
  inherit
    (lib)
    getName
    unique
    makeBinPath
    escapeShellArgs
    ;

  # Pull all the dependencies of each plugin in the list
  foldPlugins = builtins.foldl' (
    acc: next:
      acc
      ++ [next]
      ++ (foldPlugins (next.dependencies or []))
  ) [];

  packpath = let
    # Construct symlinks for each plugin to the destination in the packpath
    linkPlugins = plugins: dest:
      lib.concatMapStringsSep
      "\n"
      (plugin: "ln -vsfT ${plugin} $out/pack/${name}/${dest}/${getName
        plugin}")
      plugins;
  in
    runCommandLocal "packpath" {} ''
      mkdir -p $out/pack/${name}/{start,opt}

      ${linkPlugins (unique (foldPlugins startPlugins)) "start"}
      ${linkPlugins (unique (foldPlugins optPlugins)) "opt"}
    '';

  wrapperArgs =
    [
      "--add-flags"
      "-u"
      "--add-flags"
      "${configDir}/init.lua"
      "--add-flags"
      "--cmd"
      "--add-flags"
      "'set packpath^=${packpath}'"
      "--add-flags"
      "--cmd"
      "--add-flags"
      "'set runtimepath^=${packpath}'"
      "--add-flags"
      "--cmd"
      "--add-flags"
      "'set runtimepath^=${configDir}'"
      "--set-default"
      "NVIM_APPNAME"
      "${name}"
    ]
    ++ ["--prefix" "PATH" ":" (makeBinPath extraPackages)]
    ++ extraWrapperArgs;
in
  symlinkJoin {
    inherit name meta;
    paths = [neovim-unwrapped];
    nativeBuildInputs = [makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/nvim ${escapeShellArgs wrapperArgs}
    '';

    passthru =
      {
        inherit packpath configDir;
      }
      // extraPassthru;
  }
