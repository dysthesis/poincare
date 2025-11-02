pkgs: let
  nvimWrapper = import ../packages/poincare/wrapper.nix {
    inherit pkgs;
    self = ../..;
  };

  poincareConfig = nvimWrapper.withConfig {
    name = "poincare";
    src = ../..;
    withFennelSupport = true;
    includeRtpDirs = [
      "init.fnl"
      "fnl/"
    ];
  };

  fennelProject = pkgs.writeText "flsproject.fnl" ''
    {:fennel-path "${poincareConfig.runtimePath}/?.fnl;${poincareConfig.runtimePath}/?/init.fnl;./?.fnl;./?/init.fnl;fnl/?.fnl;fnl/?/init.fnl"
     :extra-globals "vim vim.api vim.fn vim.loop fennel.sym?"}
  '';
in
  pkgs.mkShell {
    name = "Poincare";
    packages = with pkgs; [
      nixd
      alejandra
      statix
      deadnix
      lua-language-server
      stylua
      npins
      fennel-ls
      vale
      fennel
    ];

    shellHook = ''
      ln -sf ${fennelProject} flsproject.fnl
    '';
  }
