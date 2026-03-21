{
  description = "typescript-monorepo";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    repo-lib.url = "git+https://git.dgren.dev/eric/nix-flake-lib?ref=refs/tags/v3.6.2";
    repo-lib.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      repo-lib,
      ...
    }:
    repo-lib.lib.mkRepo {
      inherit self nixpkgs;
      src = ./.;

      config = {
        shell = {
          banner = {
            style = "pretty";
            icon = "☾";
            title = "Moonrepo shell ready";
            titleColor = "GREEN";
            subtitle = "Bun + TypeScript + Varlock";
            subtitleColor = "GRAY";
            borderColor = "BLUE";
          };

          extraShellText = ''
            export PATH="$PWD/node_modules/.bin:$PATH"
          '';

          bootstrap = ''
            repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

            export BUN_INSTALL_GLOBAL_DIR="$repo_root/.tools/bun/install/global"
            export BUN_INSTALL_BIN="$repo_root/.tools/bun/bin"
            export PATH="$BUN_INSTALL_BIN:$PATH"

            mkdir -p "$BUN_INSTALL_GLOBAL_DIR" "$BUN_INSTALL_BIN"

            if [ ! -x "$BUN_INSTALL_BIN/moon" ]; then
              bun add -g @moonrepo/cli
            fi
          '';
          allowImpureBootstrap = true;
        };

        formatting = {
          programs = {
            oxfmt.enable = true;
          };

          settings = {
            oxfmt.excludes = [
              "*.css"
              "*.graphql"
              "*.hbs"
              "*.html"
              "*.md"
              "*.mdx"
              "*.mustache"
              "*.scss"
              "*.vue"
              "*.yaml"
              "*.yml"
            ];
          };
        };

        release = {
          steps = [ ];
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
            (repo-lib.lib.tools.fromCommand {
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

            (repo-lib.lib.tools.fromPackage {
              name = "Bun";
              package = pkgs.bun;
              version.args = [ "--version" ];
              banner = {
                color = "YELLOW";
                icon = "";
              };
            })
          ];

          shell = {
            packages = [
              self.packages.${system}.release
              pkgs.openbao
              pkgs.oxfmt
              pkgs.oxlint
            ];
          };

          checks = {
            format = {
              command = "oxfmt --check .";
              stage = "pre-commit";
              passFilenames = false;
              runtimeInputs = [ pkgs.oxfmt ];
            };

            typecheck = {
              command = "bun run typecheck";
              stage = "pre-push";
              passFilenames = false;
              runtimeInputs = [ pkgs.bun ];
            };

            env-check = {
              command = "bun run env:check";
              stage = "pre-push";
              passFilenames = false;
              runtimeInputs = [
                pkgs.bun
                pkgs.openbao
              ];
            };

            env-scan = {
              command = "bun run env:scan";
              stage = "pre-commit";
              passFilenames = false;
              runtimeInputs = [
                pkgs.bun
                pkgs.openbao
              ];
            };
          };
        };
    };
}
