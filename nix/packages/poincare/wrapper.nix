{ pkgs }:
let
  impl =
    args@{
      name ? "nvim-custom",
      plugins ? [ ],
      extraLua ? "",
    }:
    {
      symlinkJoin,
      neovim-unwrapped,
      makeWrapper,
      runCommandLocal,
      lib,
      writeTextFile,
    }:
    let
      inherit name plugins extraLua;

      foldPlugins = builtins.foldl' (
        acc: next:
        # Add the plugins with its dependencies to the final plugin list
        acc ++ [ next ] ++ (foldPlugins (next.dependencies or [ ]))
      ) [ ];

      pluginsWithDeps = foldPlugins plugins;

      packpath = runCommandLocal "packpath-${name}" { } ''
        mkdir -p "$out/pack/${name}/"{start,opt}
        ${lib.concatMapStringsSep "\n" (
          plugin: "ln -vsfT ${plugin} \"$out/pack/${name}/start/${lib.getName plugin}\""
        ) pluginsWithDeps}
      '';

      initLua = writeTextFile {
        name = "init-${name}.lua";
        text = ''
          ${extraLua}
        '';
      };
    in
    symlinkJoin {
      inherit name;
      paths = [ neovim-unwrapped ];
      nativeBuildInputs = [ makeWrapper ];

      # Wrap Neovim to point at our init.lua and packpath.
      postBuild = ''
        wrapProgram "$out/bin/nvim" \
          --add-flags -u \
          --add-flags ${initLua} \
          --add-flags --cmd \
          --add-flags "'set packpath^=${packpath} | set runtimepath^=${packpath}'" \
          --set-default NVIM_APPNAME nvim-custom
      '';

      passthru = {
        inherit packpath;
        config = args;
      };

      # Tell Nix what the executable name is
      meta.mainProgram = "nvim";
    };

  mk = pkgs.makeOverridable (args: pkgs.callPackage (impl args) { });
in
rec {
  default = mk { };
  withConfig = mk;
  __functor = _self: withConfig;
}
