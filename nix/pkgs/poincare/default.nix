{
  pkgs,
  craneLib,
  commonArgs,
  cargoArtifacts,
  ...
}: let
  binary = import ./binary.nix {inherit pkgs craneLib commonArgs cargoArtifacts;};
in
  pkgs.runCommandLocal "poincare-config-plugin" {} ''
    set -eu
    mkdir -p "$out/lua"

    # Find the cdylib built by cargo+crane
    lib="$(find ${binary}/lib -maxdepth 1 \
             \( -name 'libpoincare*.so' -o \
                -name 'libpoincare*.dylib' -o \
                -name 'poincare*.dll' \) \
             | head -n1)"

    if [ -z "$lib" ]; then
      echo "Could not find Rust config cdylib under ${binary}/lib" >&2
      exit 1
    fi

    # Expose it as lua module "config" so require('config') works
    cp "$lib" "$out/lua/config.so"
  ''
