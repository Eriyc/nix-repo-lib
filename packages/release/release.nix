{
  nixpkgs,
  treefmt-nix,
  git-hooks,
  releaseScriptPath ? ./release.sh,
  shellHookTemplatePath ? ../repo-lib/shell-hook.sh,
}:
import ../repo-lib/lib.nix {
  inherit
    nixpkgs
    treefmt-nix
    git-hooks
    releaseScriptPath
    shellHookTemplatePath
    ;
}
