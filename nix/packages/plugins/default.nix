{
  pkgs,
  lib,
  ...
}: let
  inherit
    (lib)
    mapAttrs'
    mapAttrs
    ;

  inherit
    (lib.attrsets)
    removeAttrs
    ;

  mkPlugin = {
    pkgs,
    src,
    pname,
    version ? src.lastModifiedDate,
  }:
    pkgs.vimUtils.buildVimPlugin {
      inherit pname src version;
    };

  npins = removeAttrs (import ./npins) ["__functor"];
  buildOne = pname: src: let
    plugin = mkPlugin {
      inherit pkgs src pname;
      version = src.revision;
    };
  in
    # TODO: Figure out a better way to handle this edge case
    if pname == "minimal-nvim"
    then
      plugin.overrideAttrs (old: {
        postPatch =
          (old.postPatch or "")
          + ''
            rm -f after/queries/lean/highlights.scm
          '';
      })
    else plugin;
in
  npins
  |> mapAttrs' (k: lib.nameValuePair (k |> lib.replaceStrings ["."] ["-"]))
  |> mapAttrs buildOne
