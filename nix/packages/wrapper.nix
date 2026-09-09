# Simple Neovim wrapper for Nix.
# Based on: https://ayats.org/blog/neovim-wrapper
{
  symlinkJoin,
  makeWrapper,
  neovim-unwrapped,
  runCommandLocal,
  lib,
  # Parameters for configuring the final derivation itself.
  name ? "poincare",
  # Plugins that must be eagerly loaded.
  eagerPlugins ? [],
  # Plugins that can be lazily loaded.
  lazyPlugins ? [],
  # Where the config is located.
  cfgDir ? ../../src,
  ...
}: let
  inherit
    (lib)
    getName
    unique
    ;

  # Wrap a plugin with its dependencies as well
  withDeps = builtins.foldl' (
    acc: next:
      acc
      ++ [next]
      ++ (withDeps (next.dependencies or []))
  ) [];

  packpath = let
    # Construct symlinks for each plugin to the destination in the packpath
    linkPlugins = dest: plugins:
      lib.concatMapStringsSep
      "\n"
      (plugin: "ln -vsfT ${plugin} $out/pack/${name}/${dest}/${getName
        plugin}")
      plugins;
  in
    runCommandLocal "packpath" {}
    # sh
    ''
      mkdir -p $out/pack/${name}/{start,opt}
      cp -r ${../../src}/* $out/


      ${eagerPlugins |> withDeps |> unique |> linkPlugins "start"}
      ${lazyPlugins |> withDeps |> unique |> linkPlugins "opt"}
    '';
in
  symlinkJoin {
    inherit name;
    paths = [neovim-unwrapped];
    nativeBuildInputs = [makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/nvim \
        --add-flags '-u' \
        --add-flags '${cfgDir}/init.lua' \
        --add-flags '--cmd' \
        --add-flags "'set packpath^=${packpath} | set runtimepath^=${packpath}'" \
        --set-default NVIM_APPNAME nvim-custom
    '';

    passthru = {
      inherit packpath;
    };
    meta.mainProgram = "nvim";
  }
