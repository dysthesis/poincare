pkgs: _poincare: let
  inherit (pkgs.lib) attrByPath findFirst;

  luacheck = findFirst (x: x != null) null (map (p: attrByPath p null pkgs) [
    ["luacheck"]
    ["luaPackages" "luacheck"]
    ["lua54Packages" "luacheck"]
    ["lua53Packages" "luacheck"]
    ["lua52Packages" "luacheck"]
    ["lua51Packages" "luacheck"]
  ]);
in
  pkgs.mkShell {
    name = "Poincare";
    packages = with pkgs;
      [
        nil
        alejandra
        statix
        deadnix
        lua-language-server
        stylua
        selene
        npins
      ]
      ++ pkgs.lib.optionals (luacheck != null) [luacheck];
  }
