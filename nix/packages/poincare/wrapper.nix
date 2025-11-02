{
  pkgs,
  self,
}:
let
  impl =
    args@{
      name ? "nvim-custom",
      plugins ? [ ],
      extraLua ? "",
      src ? self,
      # Regexes for config files to ignore, relative to the nvim directory.
      # e.g. [ "^plugin/neogit.lua" "^ftplugin/.*.lua" ]
      ignoreConfigRegexes ? [ ],
      # which paths in the config to include in the runtime path
      includeRtpDirs ? [ ],
      withFennelSupport ? false,
    }:
    {
      symlinkJoin,
      neovim-unwrapped,
      makeWrapper,
      runCommandLocal,
      lib,
      writeTextFile,
      stdenv,
      luaPackages,
    }:
    let
      inherit
        name
        plugins
        extraLua
        ;

      inherit (pkgs.lib)
        cleanSourceWith
        removePrefix
        all
        concatMapStringsSep
        optionalString
        getExe
        ;

      inherit (builtins) match;

      foldPlugins = builtins.foldl' (
        acc: next:
        # Add the plugins with its dependencies to the final plugin list
        acc ++ [ next ] ++ (foldPlugins (next.dependencies or [ ]))
      ) [ ];

      pluginsWithDeps = foldPlugins (
        plugins ++ (if withFennelSupport then [ pkgs.vimPlugins.hotpot-nvim ] else [ ])
      );

      packPath = runCommandLocal "packpath-${name}" { } ''
        mkdir -p "$out/pack/${name}/"{start,opt}
        ln -vsfT ${pkgs.vimPlugins.hotpot-nvim} \
          "$out/pack/${name}/start/${lib.getName pkgs.vimPlugins.hotpot-nvim}"
        ln -vsfT ${pkgs.vimPlugins.lz-n} \
          "$out/pack/${name}/start/${lib.getName pkgs.vimPlugins.lz-n}"
        ${lib.concatMapStringsSep "\n" (
          p:
          let
            drv = p.plugin or p;
            dir = if p ? optional && p.optional then "opt" else "start";
            nm = lib.getName drv;
          in
          "ln -vsfT ${drv} \"$out/pack/${name}/${dir}/${nm}\""
        ) pluginsWithDeps}
      '';

      # This uses the ignoreConfigRegexes list to filter
      # the nvim directory
      runtimePathSrc = cleanSourceWith {
        inherit src;
        name = "nvim-rtp-src";
        filter =
          path: _tyoe:
          let
            srcPrefix = toString src + "/";
            relPath = removePrefix srcPrefix (toString path);
          in
          all (regex: match regex relPath == null) ignoreConfigRegexes;
      };

      runtimePath = stdenv.mkDerivation {
        name = "nvim-rtp";
        src = runtimePathSrc;
        installPhase = ''
          mkdir -p $out/
          ${concatMapStringsSep "\n" (
            dir:
            #sh
            "cp -r ${dir} $out/"
          ) includeRtpDirs}
        '';
      };

      compileFennel =
        name: path:
        runCommandLocal name { } ''
          ${getExe luaPackages.fennel} --compile ${path} > $out
        '';

      initLua = writeTextFile {
        name = "init-${name}.lua";
        text = lib.concatStrings [
          # lua
          ''
            vim.opt.rtp:prepend('${runtimePath}')
            vim.loader.enable()
          ''
          (optionalString withFennelSupport (
            builtins.readFile (compileFennel "load-fennel" ./load-fennel.fnl)
          ))
          (optionalString (extraLua != "") "\n")
          extraLua
        ];
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
          --add-flags "'set packpath^=${packPath} | set runtimepath^=${packPath}'" \
          --set-default NVIM_APPNAME nvim-custom
      '';

      passthru = {
        inherit packPath runtimePath;
        config = args;
      };

      # Tell Nix what the executable name is
      meta.mainProgram = "nvim";
    };

  mk = pkgs.lib.makeOverridable (args: pkgs.callPackage (impl args) { });
in
rec {
  default = mk { };
  withConfig = mk;
  __functor = _self: withConfig;
}
