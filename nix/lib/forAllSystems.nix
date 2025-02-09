pkgs: systems: f: pkgs.lib.genAttrs systems (system: f pkgs.legacyPackages.${system})
