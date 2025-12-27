pkgs: poincare: let
  fennelProject = pkgs.writeText "flsproject.fnl" ''
    {:fennel-path "${poincare.configDir}/?.fnl;${poincare.configDir}/?/init.fnl;./?.fnl;./?/init.fnl;fnl/?.fnl;fnl/?/init.fnl"
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
      luaPackages.fennel
    ];
    shellHook = ''
      ln -sf ${fennelProject} flsproject.fnl
    '';
  }
