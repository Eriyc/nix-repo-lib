{
  flake-parts,
  nixpkgs,
  treefmt-nix,
  lefthookNix,
  releaseScriptPath ? ./release.sh,
  shellHookTemplatePath ? ../repo-lib/shell-hook.sh,
}:
import ../repo-lib/lib.nix {
  inherit
    flake-parts
    nixpkgs
    treefmt-nix
    lefthookNix
    releaseScriptPath
    shellHookTemplatePath
    ;
}
