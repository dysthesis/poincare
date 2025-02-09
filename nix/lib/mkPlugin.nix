# Taken from https://github.com/jordanisaacs/neovim-flake/blob/main/modules/lib/plugins.nix
lib: let
  inherit
    (lib)
    mapAttrs'
    nameValuePair
    removePrefix
    hasPrefix
    filterAttrs
    ;

  inherit (lib.attrsets) attrNames;

  # Get the names of all flake inputs that start with the given prefix.
  fromInputs = {
    inputs,
    prefix,
  }:
    mapAttrs'
    (n: v: nameValuePair (removePrefix prefix n) {src = v;})
    (filterAttrs (n: _: hasPrefix prefix n) inputs);

  # Use this to create a plugin from a flake input
  mkNvimPlugin = pkgs: src: pname:
    pkgs.vimUtils.buildVimPlugin {
      inherit pname src;
      version = src.lastModifiedDate;
    };
in {
  mapPlugins = pkgs: inputs: prefix:
    map
    (x: mkNvimPlugin pkgs inputs."${prefix}${x}" x)
    (attrNames
      (fromInputs {
        inherit inputs prefix;
      }));
}
