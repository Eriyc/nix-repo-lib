# flake.nix — product repo template
{
  description = "my-product";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    devshell-lib.url = "git+https://git.dgren.dev/eric/nix-flake-lib?ref=v0.0.2";
    devshell-lib.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      devshell-lib,
      ...
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          env = devshell-lib.lib.mkDevShell {
            inherit system;

            # includeStandardPackages = false; # opt out of nixfmt/gitlint/gitleaks/shfmt defaults

            extraPackages = with pkgs; [
              # add your tools here, e.g.:
              # go
              # bun
              # rustc
            ];

            features = {
              # oxfmt = true;  # enables oxfmt + oxlint from nixpkgs
            };

            formatters = {
              # shfmt.enable = true;
              # gofmt.enable = true;
            };

            formatterSettings = {
              # shfmt.options = [ "-i" "2" "-s" "-w" ];
              # oxfmt.includes = [ "*.ts" "*.tsx" "*.js" "*.json" ];
            };

            additionalHooks = {
              tests = {
                enable = true;
                entry = "echo 'No tests defined yet.'"; # replace with your test command
                pass_filenames = false;
                stages = [ "pre-push" ];
              };
              # my-hook = {
              #   enable = true;
              #   entry = "${pkgs.some-tool}/bin/some-tool";
              #   pass_filenames = false;
              # };
            };

            tools = [
              # { name = "Bun";   bin = "${pkgs.bun}/bin/bun";    versionCmd = "--version"; color = "YELLOW"; }
              # { name = "Go";    bin = "${pkgs.go}/bin/go";       versionCmd = "version";   color = "CYAN";   }
              # { name = "Rust";  bin = "${pkgs.rustc}/bin/rustc"; versionCmd = "--version"; color = "YELLOW"; }
            ];

            extraShellHook = ''
              # any repo-specific shell setup here
            '';
          };
        in
        {
          default = env.shell;
        }
      );

      checks = forAllSystems (
        system:
        let
          env = devshell-lib.lib.mkDevShell { inherit system; };
        in
        {
          inherit (env) pre-commit-check;
        }
      );

      formatter = forAllSystems (system: (devshell-lib.lib.mkDevShell { inherit system; }).formatter);

      # Optional: release command (nix run .#release)
      #
      # The release script always updates VERSION first, then:
      #   1) runs release steps in order (file writes and scripts)
      #   2) runs postVersion hook
      #   3) formats, stages, commits, tags, and pushes
      #
      # Runtime env vars available in release.run/postVersion:
      #   BASE_VERSION, CHANNEL, PRERELEASE_NUM, FULL_VERSION, FULL_TAG
      #
      # packages = forAllSystems (
      #   system:
      #   {
      #     release = devshell-lib.lib.mkRelease {
      #       inherit system;
      #
      #       release = [
      #         {
      #           file = "src/version.ts";
      #           content = ''
      #             export const APP_VERSION = "$FULL_VERSION" as const;
      #           '';
      #         }
      #         {
      #           file = "internal/version/version.go";
      #           content = ''
      #             package version
      #
      #             const Version = "$FULL_VERSION"
      #           '';
      #         }
      #         {
      #           run = ''
      #             sed -E -i "s#^([[:space:]]*my-lib\\.url = \")github:org/my-lib[^"]*(\";)#\\1github:org/my-lib?ref=$FULL_TAG\\2#" "$ROOT_DIR/flake.nix"
      #           '';
      #         }
      #       ];
      #
      #       postVersion = ''
      #         echo "Released $FULL_TAG"
      #       '';
      #     };
      #   }
      # );
    };
}
