{ nixpkgs }:
let
  lib = nixpkgs.lib;
in
{
  inherit lib;

  importPkgs = nixpkgsInput: system: import nixpkgsInput { inherit system; };

  duplicateStrings =
    names:
    lib.unique (
      builtins.filter (
        name: builtins.length (builtins.filter (candidate: candidate == name) names) > 1
      ) names
    );

  mergeUniqueAttrs =
    label: left: right:
    let
      overlap = builtins.attrNames (lib.intersectAttrs left right);
    in
    if overlap != [ ] then
      throw "repo-lib: duplicate ${label}: ${lib.concatStringsSep ", " overlap}"
    else
      left // right;

  sanitizeName = name: lib.strings.sanitizeDerivationName name;
}
