# flake.nix — product repo template
{
  description = "my-product";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    repo-lib.url = "git+https://git.dgren.dev/eric/nix-flake-lib?ref=refs/tags/v3.0.0";
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
        # includeStandardPackages = false;

        shell = {
          env = {
            # FOO = "bar";
          };

          extraShellText = ''
            # any repo-specific shell setup here
          '';

          # Impure bootstrap is available as an explicit escape hatch.
          # bootstrap = ''
          #   export GOBIN="$PWD/.tools/bin"
          #   export PATH="$GOBIN:$PATH"
          # '';
          # allowImpureBootstrap = true;
        };

        formatting = {
          programs = {
            # shfmt.enable = true;
            # gofmt.enable = true;
          };

          settings = {
            # shfmt.options = [ "-i" "2" "-s" "-w" ];
          };
        };

        checks.tests = {
          command = "echo 'No tests defined yet.'";
          stage = "pre-push";
          passFilenames = false;
        };

        release = {
          steps = [
            # {
            #   writeFile = {
            #     path = "src/version.ts";
            #     text = ''
            #       export const APP_VERSION = "$FULL_VERSION" as const;
            #     '';
            #   };
            # }
            # {
            #   replace = {
            #     path = "README.md";
            #     regex = ''^(version = ")[^"]*(")$'';
            #     replacement = ''\1$FULL_VERSION\2'';
            #   };
            # }
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

            # (repo-lib.lib.tools.fromPackage {
            #   name = "Go";
            #   package = pkgs.go;
            #   version.args = [ "version" ];
            #   banner.color = "CYAN";
            # })
          ];

          shell.packages = [
            self.packages.${system}.release
            # pkgs.go
            # pkgs.bun
          ];

          # checks.lint = {
          #   command = "go test ./...";
          #   stage = "pre-push";
          #   runtimeInputs = [ pkgs.go ];
          # };

          # packages.my-tool = pkgs.writeShellApplication {
          #   name = "my-tool";
          #   text = ''echo hello'';
          # };
        };
    };
}
