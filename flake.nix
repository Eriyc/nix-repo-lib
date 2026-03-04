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

        # ── mkDevShell ───────────────────────────────────────────────────────
        mkDevShell =
          {
            system,
            extraPackages ? [ ],
            extraShellHook ? "",
            additionalHooks ? { },
            tools ? [ ],
            includeStandardPackages ? true,
            # tools = list of { name, bin, versionCmd, color? }
            # e.g. { name = "Bun"; bin = "${pkgs.bun}/bin/bun"; versionCmd = "--version"; color = "YELLOW"; }
            formatters ? { },
            # formatters = treefmt-nix programs attrset, merged over { nixfmt.enable = true; }
            # e.g. { gofmt.enable = true; shfmt.enable = true; }
            formatterSettings ? { },
            # formatterSettings = treefmt-nix settings.formatter attrset
            # e.g. { shfmt.options = [ "-i" "2" "-s" "-w" ]; }
            features ? { },
            # features.oxfmt = true  →  adds pkgs.oxfmt + pkgs.oxlint, enables oxfmt in treefmt
          }:
          let
            pkgs = import nixpkgs { inherit system; };
            standardPackages = with pkgs; [
              nixfmt
              gitlint
              gitleaks
              shfmt
            ];
            selectedStandardPackages = pkgs.lib.optionals includeStandardPackages standardPackages;

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
              packages = selectedStandardPackages ++ extraPackages ++ oxfmtPackages;

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

        # ── mkRelease ────────────────────────────────────────────────────────
        mkRelease =
          {
            system,
            # Source of truth is always $ROOT_DIR/VERSION.
            # Format:
            #   line 1: X.Y.Z
            #   line 2: CHANNEL (stable|alpha|beta|rc|internal|...)
            #   line 3: N (prerelease number, 0 for stable)
            postVersion ? "",
            # Shell string — runs after VERSION + release steps are written/run, before git add.
            # Same env vars available.
            release ? [ ],
            # Unified list processed in declaration order:
            #   { file = "path/to/file"; content = ''...$FULL_VERSION...''; }  # write file
            #   { run = ''...shell snippet...''; }                               # run script
            # Example:
            #   release = [
            #     {
            #       file = "src/version.ts";
            #       content = ''export const APP_VERSION = "$FULL_VERSION" as const;'';
            #     }
            #     {
            #       file = "internal/version/version.go";
            #       content = ''
            #         package version
            #
            #         const Version = "$FULL_VERSION"
            #       '';
            #     }
            #     {
            #       run = ''
            #         sed -E -i "s#^([[:space:]]*my-lib\\.url = \")github:org/my-lib[^"]*(\";)#\\1github:org/my-lib?ref=$FULL_TAG\\2#" "$ROOT_DIR/flake.nix"
            #       '';
            #     }
            #   ];
            # Runtime env includes: BASE_VERSION, CHANNEL, PRERELEASE_NUM, FULL_VERSION, FULL_TAG.
            channels ? [
              "alpha"
              "beta"
              "rc"
              "internal"
            ],
            # Valid release channels beyond "stable". Validated at runtime.
            extraRuntimeInputs ? [ ],
            # Extra packages available in the release script's PATH.
          }:
          let
            pkgs = import nixpkgs { inherit system; };
            channelList = pkgs.lib.concatStringsSep " " channels;

            releaseStepsScript = pkgs.lib.concatMapStrings (
              entry:
              if entry ? file then
                ''
                  mkdir -p "$(dirname "${entry.file}")"
                  cat > "${entry.file}" << NIXEOF
                  ${entry.content}
                  NIXEOF
                  log "Generated version file: ${entry.file}"
                ''
              else if entry ? run then
                ''
                  ${entry.run}
                ''
              else
                builtins.throw "release entry must have either 'file' or 'run'"
            ) release;

            script =
              builtins.replaceStrings
                [
                  "__CHANNEL_LIST__"
                  "__RELEASE_STEPS__"
                  "__POST_VERSION__"
                ]
                [
                  channelList
                  releaseStepsScript
                  postVersion
                ]
                (builtins.readFile ./packages/release/release.sh);
          in
          pkgs.writeShellApplication {
            name = "release";
            runtimeInputs =
              with pkgs;
              [
                git
                gnugrep
                gawk
                gnused
                coreutils
              ]
              ++ extraRuntimeInputs;
            text = script;
          };

      };

      # ── packages ────────────────────────────────────────────────────────────
      packages = forAllSystems (system: {
        # Expose a no-op release package for the lib repo itself (dogfood)
        release = self.lib.mkRelease {
          inherit system;
          release = [
            {
              run = ''
                sed -E -i "s#^([[:space:]]*devshell-lib\\.url = \")git\\+https://git\\.dgren\\.dev/eric/nix-flake-lib[^\"]*(\";)#\\1git+https://git.dgren.dev/eric/nix-flake-lib?ref=$FULL_TAG\\2#" "$ROOT_DIR/template/flake.nix"
                log "Updated template/flake.nix devshell-lib ref to $FULL_TAG"

                sed -E -i "s|(nix flake new myapp -t ')git\\+https://git\\.dgren\\.dev/eric/nix-flake-lib[^']*(#default' --refresh)|\\1git+https://git.dgren.dev/eric/nix-flake-lib?ref=$FULL_TAG\\2|" "$ROOT_DIR/README.md"
                sed -E -i "s#^([[:space:]]*inputs\\.devshell-lib\\.url = \")git\\+https://git\\.dgren\\.dev/eric/nix-flake-lib[^\"]*(\";)#\\1git+https://git.dgren.dev/eric/nix-flake-lib?ref=$FULL_TAG\\2#" "$ROOT_DIR/README.md"
                log "Updated README.md devshell-lib refs to $FULL_TAG"
              '';
            }
          ];
        };
      });

      # ── devShells ───────────────────────────────────────────────────────────
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          env = self.lib.mkDevShell {
            inherit system;
            extraPackages = with pkgs; [
              self.packages.${system}.release
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

      # ── checks ──────────────────────────────────────────────────────────────
      checks = forAllSystems (
        system:
        let
          env = self.lib.mkDevShell { inherit system; };
        in
        {
          inherit (env) pre-commit-check;
        }
      );

      # ── formatter ───────────────────────────────────────────────────────────
      formatter = forAllSystems (system: (self.lib.mkDevShell { inherit system; }).formatter);

      # ── templates ───────────────────────────────────────────────────────────
      templates = {
        default = {
          path = ./template;
          description = "Product repo using devshell-lib";
        };
      };
    };
}
