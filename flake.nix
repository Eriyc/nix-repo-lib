# flake.nix — devshell-lib
{
  description = "Shared devshell boilerplate library";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    git-hooks.url = "github:cachix/git-hooks.nix";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
      git-hooks,
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
      lib = {
        mkDevShell =
          {
            system,
            extraPackages ? [ ],
            extraShellHook ? "",
            additionalHooks ? { },
            tools ? [ ],
            # tools = list of { name, bin, versionCmd, color? }
            # e.g. { name = "Bun"; bin = "${pkgs.bun}/bin/bun"; versionCmd = "--version"; color = "YELLOW"; }
            formatters ? { },
            # formatters = treefmt-nix programs attrset, merged over { nixfmt.enable = true; }
            # e.g. { gofmt.enable = true; shfmt.enable = true; }
            formatterSettings ? { },
            # formatterSettings = treefmt-nix settings.formatter attrset
            # e.g. { shfmt.options = [ "-i" "2" "-s" "-w" ]; }
            features ? { },
            # features = opt-in lib-managed behaviours
            # features.oxfmt = true  →  adds pkgs.oxfmt + pkgs.oxlint, enables oxfmt in treefmt
          }:
          let
            pkgs = import nixpkgs { inherit system; };

            oxfmtEnabled = features.oxfmt or false;
            oxfmtPackages = pkgs.lib.optionals oxfmtEnabled [
              pkgs.oxfmt
              pkgs.oxlint
            ];
            oxfmtFormatters = pkgs.lib.optionalAttrs oxfmtEnabled {
              oxfmt.enable = true;
            };

            treefmtEval = treefmt-nix.lib.evalModule pkgs {
              projectRootFile = "flake.nix";
              programs = {
                nixfmt.enable = true; # always on — every repo has a flake.nix
              }
              // oxfmtFormatters
              // formatters;
              settings.formatter = { } // formatterSettings;
            };

            pre-commit-check = git-hooks.lib.${system}.run {
              src = ./.;
              hooks = {
                treefmt = {
                  enable = true;
                  entry = "${treefmtEval.config.build.wrapper}/bin/treefmt";
                  pass_filenames = true;
                };
                gitlint.enable = true;
                gitleaks = {
                  enable = true;
                  entry = "${pkgs.gitleaks}/bin/gitleaks protect --staged";
                  pass_filenames = false;
                };
                tests = {
                  enable = true;
                  entry = "echo 'No tests defined yet.'";
                  pass_filenames = false;
                  stages = [ "pre-push" ];
                };
              }
              // additionalHooks;
            };

            toolBannerScript = pkgs.lib.concatMapStrings (
              t:
              let
                colorVar = "$" + (t.color or "YELLOW");
              in
              ''
                if command -v ${t.bin} >/dev/null 2>&1; then
                  printf "  $CYAN ${t.name}:$RESET\t${colorVar}%s$RESET\n" "$(${t.bin} ${t.versionCmd})"
                fi
              ''
            ) tools;

          in
          {
            inherit pre-commit-check;

            formatter = treefmtEval.config.build.wrapper;

            shell = pkgs.mkShell {
              packages = extraPackages ++ oxfmtPackages;

              buildInputs = pre-commit-check.enabledPackages;

              shellHook = ''
                ${pre-commit-check.shellHook}

                if [ -t 1 ]; then
                  command -v tput >/dev/null 2>&1 && tput clear || printf '\033c'
                fi

                GREEN='\033[1;32m'
                CYAN='\033[1;36m'
                YELLOW='\033[1;33m'
                BLUE='\033[1;34m'
                RESET='\033[0m'

                printf "\n$GREEN 🚀 Dev shell ready$RESET\n\n"
                ${toolBannerScript}
                printf "\n"

                ${extraShellHook}
              '';
            };
          };
      };

      # Dogfood: this repo's own dev shell using the lib above
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          env = self.lib.mkDevShell {
            inherit system;
            extraPackages = with pkgs; [
              nixfmt
              gitlint
              gitleaks
            ];
            tools = [
              {
                name = "Nix";
                bin = "${pkgs.nix}/bin/nix";
                versionCmd = "--version";
                color = "YELLOW";
              }
            ];
          };
        in
        {
          default = env.shell;
        }
      );

      checks = forAllSystems (
        system:
        let
          env = self.lib.mkDevShell { inherit system; };
        in
        {
          inherit (env) pre-commit-check;
        }
      );

      formatter = forAllSystems (system: (self.lib.mkDevShell { inherit system; }).formatter);
    };
}
