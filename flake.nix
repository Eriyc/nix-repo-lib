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
                  # command -v tput >/dev/null 2>&1 && tput clear || printf '\033c'
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
            readVersion,
            # Shell string — must print current version to stdout: "x.y.z" or "x.y.z-channel.N"
            # Example:
            #   readVersion = ''cat "$ROOT_DIR/VERSION"'';
            writeVersion,
            # Shell string — env vars available: BASE_VERSION, CHANNEL, PRERELEASE_NUM, FULL_VERSION
            # Example:
            #   writeVersion = ''echo "$FULL_VERSION" > "$ROOT_DIR/VERSION"'';
            postVersion ? "",
            # Shell string — runs after writeVersion and versionFiles, before git add.
            # Same env vars available.
            versionFiles ? [ ],
            # List of { path, template } attrsets.
            # template is a Nix function: version -> string
            # The content is fully rendered by Nix at eval time — no shell interpolation needed.
            # Example:
            #   versionFiles = [
            #     {
            #       path = "src/version.ts";
            #       template = version: ''export const APP_VERSION = "${version}" as const;'';
            #     }
            #     {
            #       path = "internal/version/version.go";
            #       template = version: ''
            #         package version
            #
            #         const Version = "${version}"
            #       '';
            #     }
            #   ];
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

            # Version files are fully rendered by Nix at eval time.
            # The shell only writes the pre-computed strings — no shell interpolation in templates.
            versionFilesScript = pkgs.lib.concatMapStrings (
              f:
              let
                # We can't call f.template here since FULL_VERSION is a runtime value.
                # Instead we pass the path and use a shell heredoc with the template
                # rendered at runtime via the VERSION env vars.
                renderedContent = f.template "$FULL_VERSION";
              in
              ''
                mkdir -p "$(dirname "${f.path}")"
                cat > "${f.path}" << 'NIXEOF'
                ${renderedContent}
                NIXEOF
                log "Generated version file: ${f.path}"
              ''
            ) versionFiles;

            script =
              builtins.replaceStrings
                [
                  "__CHANNEL_LIST__"
                  "__VERSION_FILES__"
                  "__READ_VERSION__"
                  "__WRITE_VERSION__"
                  "__POST_VERSION__"
                ]
                [
                  channelList
                  versionFilesScript
                  readVersion
                  writeVersion
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
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          # Expose a no-op release package for the lib repo itself (dogfood)
          release = self.lib.mkRelease {
            inherit system;
            readVersion = ''cat "$ROOT_DIR/VERSION"'';
            writeVersion = ''echo "$FULL_VERSION" > "$ROOT_DIR/VERSION"'';
          };
        }
      );

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
