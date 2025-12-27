{
  symlinkJoin,
  neovim-unwrapped,
  makeWrapper,
  runCommandLocal,
  vimPlugins,
  lib,
  name ? "poincare",
  packageName ? name,
  # Plugins to load eagerly on startup
  startPlugins ? [vimPlugins.nvim-treesitter.withAllGrammars],
  # Plugins to load lazily, e.g. by `:packadd`
  optPlugins ? [],
  # Init file
  init ? ../../../init.lua,
  # Optional config directory to prepend to runtimepath
  # This should contain a `lua/` subdirectory with modules referenced by `init`.
  configDir ? null,
}: let
  inherit
    (lib)
    getName
    unique
    ;

  # Pull all the dependencies of each plugin in the list
  foldPlugins = builtins.foldl' (
    acc: next:
      acc
      ++ [next]
      ++ (foldPlugins (next.dependencies or []))
  ) [];

  startPluginsWithDeps = unique (foldPlugins startPlugins);
  optPluginsWithDeps = unique (foldPlugins optPlugins);

  packpath = let
    # Construct symlinks for each plugin to the destination in the packpath
    linkPlugins = plugins: dest:
      lib.concatMapStringsSep
      "\n"
      (plugin: "ln -vsfT ${plugin} $out/pack/${packageName}/${dest}/${getName
        plugin}")
      plugins;
  in
    runCommandLocal "packpath" {} ''
      mkdir -p $out/pack/${packageName}/{start,opt}

      ${linkPlugins startPluginsWithDeps "start"}
      ${linkPlugins optPluginsWithDeps "opt"}
    '';

  mkBuild = name: init: packpath: configDir: let
    withInit = init:
    # sh
    ''
      --add-flags '-u' \
      --add-flags '${init}'
    '';
    withPackpath = packpath:
    # sh
    ''
      --add-flags '--cmd' \
      --add-flags "'set packpath^=${packpath} | set runtimepath^=${packpath}'" \
    '';
    withConfigDir = configDir:
    # sh
      if configDir == null || configDir == ""
      then ""
      else ''
        --add-flags '--cmd' \
        --add-flags "'set runtimepath^=${configDir}'" \
      '';
    withAppname = name:
    # sh
    ''
      --set-default NVIM_APPNAME ${name}
    '';
  in
    # sh
    ''
      wrapProgram $out/bin/nvim \
        ${withInit init} \
        ${withPackpath packpath} \
        ${withConfigDir configDir} \
        ${withAppname name}
    '';
in
  symlinkJoin {
    inherit name;
    paths = [neovim-unwrapped];
    nativeBuildInputs = [makeWrapper];
    postBuild = mkBuild name init packpath configDir;

    passthru = {
      inherit packpath;
    };
  }
