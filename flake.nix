# flake.nix — repo-lib
{
  description = "Pure-first repo development platform for Nix flakes";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    lefthook-nix.url = "github:sudosubin/lefthook.nix";
    lefthook-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    {
      self,
      flake-parts,
      nixpkgs,
      treefmt-nix,
      lefthook-nix,
      ...
    }:
    let
      lib = nixpkgs.lib;
      repoLib = import ./packages/repo-lib/lib.nix {
        inherit flake-parts nixpkgs treefmt-nix;
        lefthookNix = lefthook-nix;
        releaseScriptPath = ./packages/release/release.sh;
        shellHookTemplatePath = ./packages/repo-lib/shell-hook.sh;
      };
      supportedSystems = repoLib.systems.default;
      importPkgs = nixpkgsInput: system: import nixpkgsInput { inherit system; };

      projectOutputs = repoLib.mkRepo {
        inherit self nixpkgs;
        src = ./.;
        config = {
          release = {
            steps = [
              {
                replace = {
                  path = "template/flake.nix";
                  regex = ''^([[:space:]]*repo-lib\.url = ")git\+https://git\.dgren\.dev/eric/nix-flake-lib[^"]*(";)'';
                  replacement = ''\1git+https://git.dgren.dev/eric/nix-flake-lib?ref=refs/tags/$FULL_TAG\2'';
                };
              }
              {
                replace = {
                  path = "README.md";
                  regex = ''(nix flake new myapp -t ')git\+https://git\.dgren\.dev/eric/nix-flake-lib[^']*(#default' --refresh)'';
                  replacement = ''\1git+https://git.dgren.dev/eric/nix-flake-lib?ref=refs/tags/$FULL_TAG\2'';
                };
              }
              {
                replace = {
                  path = "README.md";
                  regex = ''^([[:space:]]*inputs\.repo-lib\.url = ")git\+https://git\.dgren\.dev/eric/nix-flake-lib[^"]*(";)'';
                  replacement = ''\1git+https://git.dgren.dev/eric/nix-flake-lib?ref=refs/tags/$FULL_TAG\2'';
                };
              }
            ];
          };
        };
        perSystem =
          {
            pkgs,
            system,
            ...
          }:
          {
            tools = [
              (repoLib.tools.fromCommand {
                name = "Nix";
                command = "nix";
                version = {
                  args = [ "--version" ];
                  group = 1;
                };
                banner = {
                  color = "BLUE";
                  icon = "";
                };
              })
            ];

            shell.packages = [ self.packages.${system}.release ];
          };
      };

      testChecks = lib.genAttrs supportedSystems (
        system:
        let
          pkgs = importPkgs nixpkgs system;
        in
        {
          release-tests =
            pkgs.runCommand "release-tests"
              {
                nativeBuildInputs = with pkgs; [
                  go
                  git
                ];
              }
              ''
                export HOME="$PWD/.home"
                export GOCACHE="$PWD/.go-cache"
                mkdir -p "$GOCACHE" "$HOME"
                cd ${./packages/release}
                go test ./...
                touch "$out"
              '';
        }
      );
    in
    projectOutputs
    // {
      lib = repoLib;

      templates = {
        default = {
          path = ./template;
          description = "Product repo using repo-lib";
        };
      };

      checks = lib.genAttrs supportedSystems (
        system: projectOutputs.checks.${system} // testChecks.${system}
      );
    };
}
