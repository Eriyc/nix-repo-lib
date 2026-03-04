# flake.nix — product repo template
{
  description = "my-product";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    devshell-lib.url = "github:yourorg/devshell-lib";
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
    };
}
