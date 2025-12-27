# A builder to build the Fennel source directory into Lua
{
  lib,
  stdenv,
  luaPackages,
  ...
}: {
  # Name of the derivation
  pname,
  # Version of the derivation,
  version ? "0.1.0",
  # Metadata of the derivation
  meta ? {},
  # Path to the config directory
  src,
  # Directories to preserve
  extraDirs ? [],
}: let
  # Predicate to preserve `extraDirs`
  extraDirsAbs = map (d: "${toString src}/${d}") extraDirs;
  isExtraPath = path:
    lib.any (d: path == d || lib.hasPrefix "${d}/" path) extraDirsAbs;

  findExclude =
    lib.concatStringsSep " " (map (d: "-not -path \"$src/${d}/*\"") extraDirs);
  extraDirsArgs =
    lib.concatStringsSep " " (map lib.escapeShellArg extraDirs);

  # Filter for Fennel files.
  src' =
    builtins.filterSource (
      path: type: let
        pathStr = toString path;
      in
        # Do we want to explicitly preserve this path?
        isExtraPath pathStr
        # Is it a directory?
        || type == "directory"
        # Is it fennel?
        || lib.hasSuffix ".fnl" (baseNameOf path)
    )
    src;
in
  stdenv.mkDerivation {
    inherit pname version meta;

    src = src';
    nativeBuildInputs = [luaPackages.fennel];

    dontUnpack = true;
    phases = ["installPhase"];

    installPhase = ''
      runHook preInstall
      set -euo pipefail

      mkdir -p "$out"

      while IFS= read -r -d $'\0' inFile; do
        rel="''${inFile#"$src"/}"

        case "$rel" in
          fnl/*) outRel="lua/''${rel#fnl/}" ;;
          *)     outRel="$rel" ;;
        esac

        outFile="$out/''${outRel%.fnl}.lua"

        mkdir -p "$(dirname "$outFile")"
        tmp="$(mktemp "''${outFile}.XXXXXX")"
        fennel --compile "$inFile" > "$tmp"
        mv -f "$tmp" "$outFile"
      done < <(find "$src" -type f -name '*.fnl' ${findExclude} -print0)

      for dir in ${extraDirsArgs}; do
        if [ -d "$src/$dir" ]; then
          mkdir -p "$out/$dir"
          cp -a "$src/$dir/." "$out/$dir"
        fi
      done

      runHook postInstall
    '';
  }
