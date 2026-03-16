#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${REPO_LIB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RELEASE_TEMPLATE="$ROOT_DIR/packages/release/release.sh"
NIXPKGS_FLAKE_PATH="${NIXPKGS_FLAKE_PATH:-}"
CURRENT_LOG=""
QC_SEEN_TAGS=()

if [[ -z "$NIXPKGS_FLAKE_PATH" ]]; then
	NIXPKGS_FLAKE_PATH="$(nix eval --raw --impure --expr "(builtins.getFlake (toString ${ROOT_DIR})).inputs.nixpkgs.outPath")"
fi

fail() {
	echo "[test] FAIL: $*" >&2
	if [[ -n "$CURRENT_LOG" && -f "$CURRENT_LOG" ]]; then
		echo "[test] ---- captured output ----" >&2
		cat "$CURRENT_LOG" >&2
		echo "[test] -------------------------" >&2
	fi
	exit 1
}

assert_eq() {
	local expected="$1"
	local actual="$2"
	local message="$3"
	if [[ "$expected" != "$actual" ]]; then
		fail "$message (expected '$expected', got '$actual')"
	fi
}

assert_contains() {
	local needle="$1"
	local haystack_file="$2"
	local message="$3"
	if ! grep -Fq -- "$needle" "$haystack_file"; then
		fail "$message (missing '$needle')"
	fi
}

run_capture_ok() {
	local description="$1"
	shift
	if ! "$@" >>"$CURRENT_LOG" 2>&1; then
		fail "$description"
	fi
}

make_release_script() {
	local target="$1"
	make_release_script_with_content "$target" ":" ":"
}

make_release_script_with_content() {
	local target="$1"
	local release_steps="$2"
	local post_version="$3"
	local script

	script="$(cat "$RELEASE_TEMPLATE")"
	script="${script//__CHANNEL_LIST__/alpha beta rc internal}"
	script="${script//__RELEASE_STEPS__/$release_steps}"
	script="${script//__POST_VERSION__/$post_version}"
	printf '%s' "$script" >"$target"
	chmod +x "$target"
}

setup_repo() {
	local repo_dir="$1"
	local remote_dir="$2"

	mkdir -p "$repo_dir"
	run_capture_ok "setup_repo: git init failed" git -C "$repo_dir" init
	run_capture_ok "setup_repo: git config user.name failed" git -C "$repo_dir" config user.name "Release Test"
	run_capture_ok "setup_repo: git config user.email failed" git -C "$repo_dir" config user.email "release-test@example.com"
	run_capture_ok "setup_repo: git config commit.gpgsign failed" git -C "$repo_dir" config commit.gpgsign false
	run_capture_ok "setup_repo: git config tag.gpgsign failed" git -C "$repo_dir" config tag.gpgsign false

	cat >"$repo_dir/flake.nix" <<'EOF'
{
  description = "release test";
  outputs = { self }: { };
}
EOF

	printf '1.0.0\nstable\n0\n' >"$repo_dir/VERSION"
	run_capture_ok "setup_repo: git add failed" git -C "$repo_dir" add -A
	run_capture_ok "setup_repo: git commit failed" git -C "$repo_dir" commit -m "init"

	run_capture_ok "setup_repo: git init --bare failed" git init --bare "$remote_dir"
	run_capture_ok "setup_repo: git remote add failed" git -C "$repo_dir" remote add origin "$remote_dir"
	run_capture_ok "setup_repo: initial push failed" git -C "$repo_dir" push -u origin HEAD
}

version_from_file() {
	local repo_dir="$1"
	local base channel n
	base="$(sed -n '1p' "$repo_dir/VERSION" | tr -d '\r')"
	channel="$(sed -n '2p' "$repo_dir/VERSION" | tr -d '\r')"
	n="$(sed -n '3p' "$repo_dir/VERSION" | tr -d '\r')"

	if [[ -z "$channel" || "$channel" == "stable" ]]; then
		echo "$base"
	else
		echo "$base-$channel.$n"
	fi
}

prepare_case_repo() {
	local repo_dir="$1"
	local remote_dir="$2"

	setup_repo "$repo_dir" "$remote_dir"
	make_release_script "$repo_dir/release"

	mkdir -p "$repo_dir/bin"
	cat >"$repo_dir/bin/nix" <<'EOF'
#!/usr/bin/env bash
if [[ "${1-}" == "fmt" ]]; then
	exit 0
fi
echo "unexpected nix invocation: $*" >&2
exit 1
EOF
	chmod +x "$repo_dir/bin/nix"
}

prepare_case_repo_with_release_script() {
	local repo_dir="$1"
	local remote_dir="$2"
	local release_steps="$3"
	local post_version="$4"

	setup_repo "$repo_dir" "$remote_dir"
	make_release_script_with_content "$repo_dir/release" "$release_steps" "$post_version"

	mkdir -p "$repo_dir/bin"
	cat >"$repo_dir/bin/nix" <<'EOF'
#!/usr/bin/env bash
if [[ "${1-}" == "fmt" ]]; then
	exit 0
fi
echo "unexpected nix invocation: $*" >&2
exit 1
EOF
	chmod +x "$repo_dir/bin/nix"
}

run_release() {
	local repo_dir="$1"
	shift
	(
		cd "$repo_dir"
		PATH="$repo_dir/bin:$PATH" ./release "$@"
	)
}

run_expect_failure() {
	local description="$1"
	shift
	if "$@" >>"$CURRENT_LOG" 2>&1; then
		fail "$description (expected failure)"
	fi
}

write_mk_repo_flake() {
	local repo_dir="$1"
	cat >"$repo_dir/flake.nix" <<EOF
{
  description = "mkRepo ok";

  inputs = {
    nixpkgs.url = "path:${NIXPKGS_FLAKE_PATH}";
    repo-lib.url = "path:${ROOT_DIR}";
    repo-lib.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, repo-lib, ... }:
    repo-lib.lib.mkRepo {
      inherit self nixpkgs;
      src = ./.;

      config = {
        checks.tests = {
          command = "echo test";
          stage = "pre-push";
          passFilenames = false;
        };

        release = {
          steps = [ ];
        };
      };

      perSystem = { pkgs, system, ... }: {
        tools = [
          (repo-lib.lib.tools.fromPackage {
            name = "Hello";
            package = pkgs.hello;
            exe = "hello";
            version.args = [ "--version" ];
          })
        ];

        shell.packages = [
          self.packages.\${system}.release
        ];

        packages.example = pkgs.writeShellApplication {
          name = "example";
          text = ''
            echo example
          '';
        };
      };
    };
}
EOF
}

write_mk_repo_command_tool_flake() {
	local repo_dir="$1"
	cat >"$repo_dir/flake.nix" <<EOF
{
  description = "mkRepo command-backed tool";

  inputs = {
    nixpkgs.url = "path:${NIXPKGS_FLAKE_PATH}";
    repo-lib.url = "path:${ROOT_DIR}";
    repo-lib.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, repo-lib, ... }:
    repo-lib.lib.mkRepo {
      inherit self nixpkgs;
      src = ./.;

      config.release = {
        steps = [ ];
      };

      perSystem = { system, ... }: {
        tools = [
          (repo-lib.lib.tools.fromCommand {
            name = "Nix";
            command = "nix";
            version.args = [ "--version" ];
            banner = {
              color = "BLUE";
              icon = "";
            };
          })
        ];

        shell.packages = [
          self.packages.\${system}.release
        ];
      };
    };
}
EOF
}

write_mk_repo_lefthook_flake() {
	local repo_dir="$1"
	cat >"$repo_dir/flake.nix" <<EOF
{
  description = "mkRepo raw lefthook config";

  inputs = {
    nixpkgs.url = "path:${NIXPKGS_FLAKE_PATH}";
    repo-lib.url = "path:${ROOT_DIR}";
    repo-lib.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, repo-lib, ... }:
    repo-lib.lib.mkRepo {
      inherit self nixpkgs;
      src = ./.;

      config = {
        checks.tests = {
          command = "echo test";
          stage = "pre-push";
          passFilenames = false;
        };

        lefthook.pre-push.commands.tests.stage_fixed = true;

        release.steps = [ ];
      };
    };
}
EOF
}

init_git_repo() {
	local repo_dir="$1"

	run_capture_ok "init_git_repo: git init failed" git -C "$repo_dir" init
	run_capture_ok "init_git_repo: git config user.name failed" git -C "$repo_dir" config user.name "Repo Lib Test"
	run_capture_ok "init_git_repo: git config user.email failed" git -C "$repo_dir" config user.email "repo-lib-test@example.com"
	run_capture_ok "init_git_repo: git add failed" git -C "$repo_dir" add flake.nix
	run_capture_ok "init_git_repo: git commit failed" git -C "$repo_dir" commit -m "init"
}

write_tool_failure_flake() {
	local repo_dir="$1"
	cat >"$repo_dir/flake.nix" <<EOF
{
  description = "mkRepo tool failure";

  inputs = {
    nixpkgs.url = "path:${NIXPKGS_FLAKE_PATH}";
    repo-lib.url = "path:${ROOT_DIR}";
    repo-lib.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, repo-lib, ... }:
    repo-lib.lib.mkRepo {
      inherit self nixpkgs;
      src = ./.;

      config.release = {
        steps = [ ];
      };

      perSystem = { pkgs, ... }: {
        tools = [
          (repo-lib.lib.tools.fromPackage {
            name = "Hello";
            package = pkgs.hello;
            exe = "hello";
            version.args = [ "--definitely-invalid" ];
          })
        ];
      };
    };
}
EOF
}

write_impure_bootstrap_flake() {
	local repo_dir="$1"
	cat >"$repo_dir/flake.nix" <<EOF
{
  description = "mkRepo bootstrap validation";

  inputs = {
    nixpkgs.url = "path:${NIXPKGS_FLAKE_PATH}";
    repo-lib.url = "path:${ROOT_DIR}";
    repo-lib.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, repo-lib, ... }:
    repo-lib.lib.mkRepo {
      inherit self nixpkgs;
      src = ./.;

      config.shell.bootstrap = ''
        echo hi
      '';
    };
}
EOF
}

write_release_replace_backref_flake() {
	local repo_dir="$1"
	cat >"$repo_dir/flake.nix" <<EOF
{
	description = "mkRepo release replace backrefs";

	inputs = {
		nixpkgs.url = "path:${NIXPKGS_FLAKE_PATH}";
		repo-lib.url = "path:${ROOT_DIR}";
		repo-lib.inputs.nixpkgs.follows = "nixpkgs";
	};

	outputs = { self, nixpkgs, repo-lib, ... }:
		repo-lib.lib.mkRepo {
			inherit self nixpkgs;
			src = ./.;

			config.release = {
				steps = [
					{
						replace = {
							path = "template/flake.nix";
							regex = ''^([[:space:]]*repo-lib\.url = ")[^"]*(";)$'';
							replacement = ''\1git+https://example.invalid/repo-lib?ref=refs/tags/\$FULL_TAG\2'';
						};
					}
				];
			};
		};
}
EOF
}

write_legacy_flake() {
	local repo_dir="$1"
	cat >"$repo_dir/flake.nix" <<EOF
{
  description = "legacy api";

  inputs = {
    nixpkgs.url = "path:${NIXPKGS_FLAKE_PATH}";
    repo-lib.url = "path:${ROOT_DIR}";
    repo-lib.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, nixpkgs, repo-lib, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          env = repo-lib.lib.mkDevShell {
            inherit system;
            nixpkgsInput = nixpkgs;
            src = ./.;
            extraPackages = [ self.packages.\${system}.release ];
            tools = [
              {
                name = "Nix";
                bin = "\${pkgs.nix}/bin/nix";
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
          env = repo-lib.lib.mkDevShell {
            inherit system;
            nixpkgsInput = nixpkgs;
            src = ./.;
          };
        in
        {
          inherit (env) lefthook-check;
        }
      );

      formatter = forAllSystems (
        system:
        (repo-lib.lib.mkDevShell {
          inherit system;
          nixpkgsInput = nixpkgs;
          src = ./.;
        }).formatter
      );

      packages = forAllSystems (system: {
        release = repo-lib.lib.mkRelease {
          inherit system;
          nixpkgsInput = nixpkgs;
        };
      });
    };
}
EOF
}

write_template_fixture() {
	local repo_dir="$1"
	mkdir -p "$repo_dir"
	cp -R "$ROOT_DIR/template/." "$repo_dir/"
	sed -i.bak \
		-e "s|git+https://git.dgren.dev/eric/nix-flake-lib?ref=refs/tags/v[0-9.]*|path:${ROOT_DIR}|" \
		-e "s|github:nixos/nixpkgs?ref=nixos-unstable|path:${NIXPKGS_FLAKE_PATH}|" \
		"$repo_dir/flake.nix"
	rm -f "$repo_dir/flake.nix.bak"
}

qc_version_cmp() {
	# Returns: 0 if equal, 1 if v1 > v2, 2 if v1 < v2
	local v1="$1" v2="$2"
	[[ $v1 == "$v2" ]] && return 0

	local base1="" pre1="" base2="" pre2=""
	if [[ $v1 =~ ^([0-9]+\.[0-9]+\.[0-9]+)-(.+)$ ]]; then
		base1="${BASH_REMATCH[1]}"
		pre1="${BASH_REMATCH[2]}"
	else
		base1="$v1"
	fi
	if [[ $v2 =~ ^([0-9]+\.[0-9]+\.[0-9]+)-(.+)$ ]]; then
		base2="${BASH_REMATCH[1]}"
		pre2="${BASH_REMATCH[2]}"
	else
		base2="$v2"
	fi

	if [[ $base1 != "$base2" ]]; then
		local highest_base
		highest_base=$(printf '%s\n%s\n' "$base1" "$base2" | sort -V | tail -n1)
		[[ $highest_base == "$base1" ]] && return 1 || return 2
	fi

	[[ -z $pre1 && -n $pre2 ]] && return 1
	[[ -n $pre1 && -z $pre2 ]] && return 2
	[[ -z $pre1 && -z $pre2 ]] && return 0

	local highest_pre
	highest_pre=$(printf '%s\n%s\n' "$pre1" "$pre2" | sort -V | tail -n1)
	[[ $highest_pre == "$pre1" ]] && return 1 || return 2
}

qc_parse_base_version() {
	local v="$1"
	if [[ ! $v =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
		return 1
	fi
	QC_MAJOR="${BASH_REMATCH[1]}"
	QC_MINOR="${BASH_REMATCH[2]}"
	QC_PATCH="${BASH_REMATCH[3]}"
	return 0
}

qc_parse_full_version() {
	local v="$1"
	QC_CHANNEL="stable"
	QC_PRERELEASE_NUM=""

	if [[ $v =~ ^([0-9]+\.[0-9]+\.[0-9]+)-([a-zA-Z]+)\.([0-9]+)$ ]]; then
		QC_BASE_VERSION="${BASH_REMATCH[1]}"
		QC_CHANNEL="${BASH_REMATCH[2]}"
		QC_PRERELEASE_NUM="${BASH_REMATCH[3]}"
	elif [[ $v =~ ^([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
		QC_BASE_VERSION="${BASH_REMATCH[1]}"
	else
		return 1
	fi

	qc_parse_base_version "$QC_BASE_VERSION"
}

qc_validate_channel() {
	local channel="$1"
	[[ $channel == "stable" || $channel == "alpha" || $channel == "beta" || $channel == "rc" || $channel == "internal" ]]
}

qc_compute_full_version() {
	if [[ $QC_CHANNEL == "stable" || -z $QC_CHANNEL ]]; then
		QC_FULL_VERSION="$QC_BASE_VERSION"
	else
		QC_FULL_VERSION="$QC_BASE_VERSION-$QC_CHANNEL.${QC_PRERELEASE_NUM:-1}"
	fi
}

qc_bump_base_version() {
	qc_parse_base_version "$QC_BASE_VERSION"
	case "$1" in
	major)
		QC_MAJOR=$((QC_MAJOR + 1))
		QC_MINOR=0
		QC_PATCH=0
		;;
	minor)
		QC_MINOR=$((QC_MINOR + 1))
		QC_PATCH=0
		;;
	patch)
		QC_PATCH=$((QC_PATCH + 1))
		;;
	esac
	QC_BASE_VERSION="$QC_MAJOR.$QC_MINOR.$QC_PATCH"
}

qc_oracle_init() {
	QC_STATE_BASE="1.0.0"
	QC_STATE_CHANNEL="stable"
	QC_STATE_PRE=""
	QC_SEEN_TAGS=()
}

qc_seen_tag() {
	local tag="$1"
	local existing
	for existing in "${QC_SEEN_TAGS[@]:-}"; do
		if [[ "$existing" == "$tag" ]]; then
			return 0
		fi
	done
	return 1
}

qc_oracle_current_full() {
	QC_BASE_VERSION="$QC_STATE_BASE"
	QC_CHANNEL="$QC_STATE_CHANNEL"
	QC_PRERELEASE_NUM="$QC_STATE_PRE"
	qc_compute_full_version
	echo "$QC_FULL_VERSION"
}

qc_pick_channel() {
	local channels=(alpha beta rc internal)
	echo "${channels[RANDOM % ${#channels[@]}]}"
}

qc_build_random_command() {
	local current_full="$1"
	QC_CMD_ARGS=()

	local mode=$((RANDOM % 7))
	case "$mode" in
	0)
		QC_CMD_ARGS=(patch)
		;;
	1)
		local bumps=(major minor patch)
		QC_CMD_ARGS=("${bumps[RANDOM % ${#bumps[@]}]}")
		;;
	2)
		local bumps=(major minor patch)
		QC_CMD_ARGS=("${bumps[RANDOM % ${#bumps[@]}]}" "$(qc_pick_channel)")
		;;
	3)
		QC_CMD_ARGS=("$(qc_pick_channel)")
		;;
	4)
		if (( RANDOM % 2 == 0 )); then
			QC_CMD_ARGS=(stable)
		else
			QC_CMD_ARGS=(full)
		fi
		;;
	5)
		QC_CMD_ARGS=(set "$current_full")
		;;
	6)
		qc_parse_base_version "$QC_STATE_BASE"
		if (( RANDOM % 2 == 0 )); then
			QC_CMD_ARGS=(set "$((QC_MAJOR + 1)).0.0")
		else
			QC_CMD_ARGS=(set "$QC_STATE_BASE-$(qc_pick_channel).1")
		fi
		;;
	esac
}

qc_oracle_apply() {
	local current_full
	current_full="$(qc_oracle_current_full)"

	QC_EXPECT_SUCCESS=0
	QC_EXPECT_VERSION="$current_full"

	local action="${1-}"
	shift || true

	if [[ $action == "set" ]]; then
		local newv="${1-}"
		[[ -z $newv ]] && return 0
		qc_parse_full_version "$newv" || return 0
		qc_validate_channel "$QC_CHANNEL" || return 0
		if [[ $QC_STATE_CHANNEL != "stable" && $QC_CHANNEL == "stable" ]]; then
			return 0
		fi
		qc_compute_full_version
		local cmp_status=0
		qc_version_cmp "$QC_FULL_VERSION" "$current_full" || cmp_status=$?
		if [[ $cmp_status -eq 0 || $cmp_status -eq 2 ]]; then
			return 0
		fi
		if qc_seen_tag "v$QC_FULL_VERSION"; then
			return 0
		fi

		QC_STATE_BASE="$QC_BASE_VERSION"
		QC_STATE_CHANNEL="$QC_CHANNEL"
		QC_STATE_PRE="$QC_PRERELEASE_NUM"
		QC_EXPECT_SUCCESS=1
		QC_EXPECT_VERSION="$QC_FULL_VERSION"
		QC_SEEN_TAGS+=("v$QC_FULL_VERSION")
		return 0
	fi

	local part="" target_channel="" was_channel_only=0
	case "$action" in
	"")
		part="patch"
		;;
	major | minor | patch)
		part="$action"
		target_channel="${1-}"
		if [[ -n ${1-} ]]; then
			shift || true
			[[ -n ${1-} ]] && return 0
		fi
		;;
	stable | full)
		[[ -n ${1-} ]] && return 0
		target_channel="stable"
		;;
	alpha | beta | rc | internal)
		[[ -n ${1-} ]] && return 0
		target_channel="$action"
		was_channel_only=1
		;;
	*)
		return 0
		;;
	esac

	[[ -z $target_channel ]] && target_channel="$QC_STATE_CHANNEL"
	[[ $target_channel == "full" ]] && target_channel="stable"
	qc_validate_channel "$target_channel" || return 0
	if [[ $QC_STATE_CHANNEL != "stable" && $target_channel == "stable" && $action != "stable" && $action != "full" ]]; then
		return 0
	fi

	if [[ -z $part && $was_channel_only -eq 1 && $QC_STATE_CHANNEL == "stable" && $target_channel != "stable" ]]; then
		part="patch"
	fi

	QC_BASE_VERSION="$QC_STATE_BASE"
	QC_CHANNEL="$QC_STATE_CHANNEL"
	QC_PRERELEASE_NUM="$QC_STATE_PRE"

	local old_base="$QC_BASE_VERSION"
	local old_channel="$QC_CHANNEL"
	local old_pre="$QC_PRERELEASE_NUM"

	[[ -n $part ]] && qc_bump_base_version "$part"

	if [[ $target_channel == "stable" ]]; then
		QC_CHANNEL="stable"
		QC_PRERELEASE_NUM=""
	else
		if [[ $QC_BASE_VERSION == "$old_base" && $target_channel == "$old_channel" && -n $old_pre ]]; then
			QC_PRERELEASE_NUM=$((old_pre + 1))
		else
			QC_PRERELEASE_NUM=1
		fi
		QC_CHANNEL="$target_channel"
	fi

	qc_compute_full_version
	if [[ $QC_FULL_VERSION == "$current_full" ]]; then
		return 0
	fi
	if qc_seen_tag "v$QC_FULL_VERSION"; then
		return 0
	fi

	QC_STATE_BASE="$QC_BASE_VERSION"
	QC_STATE_CHANNEL="$QC_CHANNEL"
	QC_STATE_PRE="$QC_PRERELEASE_NUM"
	QC_EXPECT_SUCCESS=1
	QC_EXPECT_VERSION="$QC_FULL_VERSION"
	QC_SEEN_TAGS+=("v$QC_FULL_VERSION")
}

run_randomized_quickcheck_cases() {
	local case_name="randomized quickcheck transitions"
	local trials="${QUICKCHECK_TRIALS:-20}"
	local max_steps="${QUICKCHECK_MAX_STEPS:-7}"

	local trial
	for ((trial = 1; trial <= trials; trial++)); do
		local workdir
		workdir="$(mktemp -d)"
		local repo_dir="$workdir/repo"
		local remote_dir="$workdir/remote.git"
		local setup_log="$workdir/setup.log"
		CURRENT_LOG="$setup_log"

		prepare_case_repo "$repo_dir" "$remote_dir"
		qc_oracle_init

		local steps=$((1 + RANDOM % max_steps))
		local step
		for ((step = 1; step <= steps; step++)); do
			local step_log="$workdir/trial-${trial}-step-${step}.log"
			local before_version
			before_version="$(version_from_file "$repo_dir")"
			local cmd_display=""
			local step_result=""
			local before_head
			before_head="$(git -C "$repo_dir" rev-parse HEAD)"

			local oracle_before
			oracle_before="$(qc_oracle_current_full)"
			qc_build_random_command "$oracle_before"
			qc_oracle_apply "${QC_CMD_ARGS[@]}"
			cmd_display="${QC_CMD_ARGS[*]}"

			{
				echo "[test] randomized trial=$trial/$trials step=$step/$steps"
				echo "[test] command: ${QC_CMD_ARGS[*]}"
				echo "[test] expect_success=$QC_EXPECT_SUCCESS expect_version=$QC_EXPECT_VERSION"
			} >"$step_log"
			CURRENT_LOG="$step_log"

			set +e
			run_release "$repo_dir" "${QC_CMD_ARGS[@]}" >>"$step_log" 2>&1
			local status=$?
			set -e

			if [[ $QC_EXPECT_SUCCESS -eq 1 ]]; then
				if [[ $status -ne 0 ]]; then
					fail "$case_name: trial $trial step $step expected success for '${QC_CMD_ARGS[*]}'"
				fi

				local got_version
				got_version="$(version_from_file "$repo_dir")"
				assert_eq "$QC_EXPECT_VERSION" "$got_version" "$case_name: trial $trial step $step VERSION mismatch for '${QC_CMD_ARGS[*]}'"
				step_result="$got_version"

				if ! git -C "$repo_dir" tag --list | grep -qx "v$QC_EXPECT_VERSION"; then
					fail "$case_name: trial $trial step $step expected tag v$QC_EXPECT_VERSION for '${QC_CMD_ARGS[*]}'"
				fi
			else
				if [[ $status -eq 0 ]]; then
					fail "$case_name: trial $trial step $step expected failure for '${QC_CMD_ARGS[*]}'"
				fi

				local got_version
				got_version="$(version_from_file "$repo_dir")"
				assert_eq "$before_version" "$got_version" "$case_name: trial $trial step $step VERSION changed on failure for '${QC_CMD_ARGS[*]}'"
				step_result="fail (unchanged: $got_version)"

				local after_head
				after_head="$(git -C "$repo_dir" rev-parse HEAD)"
				assert_eq "$before_head" "$after_head" "$case_name: trial $trial step $step HEAD changed on failure for '${QC_CMD_ARGS[*]}'"
			fi

			echo "[test] PASS: randomized quickcheck trial $trial/$trials step $step/$steps from $before_version run '$cmd_display' -> $step_result" >&2
		done

		echo "[test] PASS: randomized quickcheck trial $trial/$trials" >&2

		rm -rf "$workdir"
		CURRENT_LOG=""
	done

	echo "[test] PASS: $case_name ($trials trials)" >&2
}

run_case() {
	local case_name="$1"
	local command_args="$2"
	local expected_version="$3"

	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/repo"
	local remote_dir="$workdir/remote.git"
	CURRENT_LOG="$workdir/case.log"

	prepare_case_repo "$repo_dir" "$remote_dir"

	run_capture_ok "$case_name: release command failed ($command_args)" run_release "$repo_dir" $command_args

	local got_version
	got_version="$(version_from_file "$repo_dir")"
	assert_eq "$expected_version" "$got_version" "$case_name: VERSION mismatch"

	if ! git -C "$repo_dir" tag --list | grep -qx "v$expected_version"; then
		fail "$case_name: expected tag v$expected_version was not created"
	fi

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_set_prerelease_then_full_case() {
	local case_name="set prerelease then full promotes to stable"

	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/repo"
	local remote_dir="$workdir/remote.git"
	CURRENT_LOG="$workdir/case.log"

	prepare_case_repo "$repo_dir" "$remote_dir"

	run_capture_ok "$case_name: release set failed" run_release "$repo_dir" set 1.1.5-beta.1
	run_capture_ok "$case_name: release full failed" run_release "$repo_dir" full

	local got_version
	got_version="$(version_from_file "$repo_dir")"
	assert_eq "1.1.5" "$got_version" "$case_name: VERSION mismatch"

	if ! git -C "$repo_dir" tag --list | grep -qx "v1.1.5"; then
		fail "$case_name: expected tag v1.1.5 was not created"
	fi

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_stable_then_beta_cannot_reuse_same_base_case() {
	local case_name="stable release cannot go back to same-base beta"

	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/repo"
	local remote_dir="$workdir/remote.git"
	CURRENT_LOG="$workdir/case.log"

	prepare_case_repo "$repo_dir" "$remote_dir"

	run_capture_ok "$case_name: initial beta release failed" run_release "$repo_dir" beta
	run_capture_ok "$case_name: stable promotion failed" run_release "$repo_dir" full
	run_capture_ok "$case_name: second beta release failed" run_release "$repo_dir" beta

	local got_version
	got_version="$(version_from_file "$repo_dir")"
	assert_eq "1.0.2-beta.1" "$got_version" "$case_name: VERSION mismatch"

	if ! git -C "$repo_dir" tag --list | grep -qx "v1.0.1"; then
		fail "$case_name: expected stable tag v1.0.1 was not created"
	fi

	if ! git -C "$repo_dir" tag --list | grep -qx "v1.0.2-beta.1"; then
		fail "$case_name: expected tag v1.0.2-beta.1 was not created"
	fi

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_set_stable_then_full_noop_case() {
	local case_name="set stable then full fails with no-op"

	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/repo"
	local remote_dir="$workdir/remote.git"
	CURRENT_LOG="$workdir/case.log"

	prepare_case_repo "$repo_dir" "$remote_dir"

	run_capture_ok "$case_name: release set failed" run_release "$repo_dir" set 1.1.5

	local before_head
	before_head="$(git -C "$repo_dir" rev-parse HEAD)"

	local err_file="$workdir/full.err"
	set +e
	run_release "$repo_dir" full >"$err_file" 2>&1
	local status=$?
	set -e
	cat "$err_file" >>"$CURRENT_LOG"

	if [[ $status -eq 0 ]]; then
		fail "$case_name: expected release full to fail on no-op version"
	fi

	assert_contains "Version 1.1.5 is already current; nothing to do." "$err_file" "$case_name: missing no-op message"

	local after_head
	after_head="$(git -C "$repo_dir" rev-parse HEAD)"
	assert_eq "$before_head" "$after_head" "$case_name: HEAD changed despite no-op failure"

	local got_version
	got_version="$(version_from_file "$repo_dir")"
	assert_eq "1.1.5" "$got_version" "$case_name: VERSION changed after no-op failure"

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_set_stable_from_prerelease_requires_full_case() {
	local case_name="set stable from prerelease requires full"

	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/repo"
	local remote_dir="$workdir/remote.git"
	CURRENT_LOG="$workdir/case.log"

	prepare_case_repo "$repo_dir" "$remote_dir"

	run_capture_ok "$case_name: release set prerelease failed" run_release "$repo_dir" set 1.1.5-beta.1

	local before_head
	before_head="$(git -C "$repo_dir" rev-parse HEAD)"

	local err_file="$workdir/set-stable.err"
	set +e
	run_release "$repo_dir" set 1.1.5 >"$err_file" 2>&1
	local status=$?
	set -e
	cat "$err_file" >>"$CURRENT_LOG"

	if [[ $status -eq 0 ]]; then
		fail "$case_name: expected release set stable to fail from prerelease"
	fi

	assert_contains "promote using 'stable' or 'full' only" "$err_file" "$case_name: missing guardrail message"

	local after_head
	after_head="$(git -C "$repo_dir" rev-parse HEAD)"
	assert_eq "$before_head" "$after_head" "$case_name: HEAD changed despite guardrail failure"

	local got_version
	got_version="$(version_from_file "$repo_dir")"
	assert_eq "1.1.5-beta.1" "$got_version" "$case_name: VERSION changed after guardrail failure"

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_patch_stable_from_prerelease_requires_full_case() {
	local case_name="patch stable from prerelease requires full"

	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/repo"
	local remote_dir="$workdir/remote.git"
	CURRENT_LOG="$workdir/case.log"

	prepare_case_repo "$repo_dir" "$remote_dir"

	run_capture_ok "$case_name: release set prerelease failed" run_release "$repo_dir" set 1.1.5-beta.1

	local before_head
	before_head="$(git -C "$repo_dir" rev-parse HEAD)"

	local err_file="$workdir/patch-stable.err"
	set +e
	run_release "$repo_dir" patch stable >"$err_file" 2>&1
	local status=$?
	set -e
	cat "$err_file" >>"$CURRENT_LOG"

	if [[ $status -eq 0 ]]; then
		fail "$case_name: expected release patch stable to fail from prerelease"
	fi

	assert_contains "promote using 'stable' or 'full' only" "$err_file" "$case_name: missing guardrail message"

	local after_head
	after_head="$(git -C "$repo_dir" rev-parse HEAD)"
	assert_eq "$before_head" "$after_head" "$case_name: HEAD changed despite guardrail failure"

	local got_version
	got_version="$(version_from_file "$repo_dir")"
	assert_eq "1.1.5-beta.1" "$got_version" "$case_name: VERSION changed after guardrail failure"

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_structured_release_steps_case() {
	local case_name="structured release steps update files"
	local release_steps
	local post_version

	read -r -d '' release_steps <<'EOF' || true
target_path="$ROOT_DIR/generated/version.txt"
mkdir -p "$(dirname "$target_path")"
cat >"$target_path" << NIXEOF
$FULL_VERSION
NIXEOF
log "Generated version file: generated/version.txt"

target_path="$ROOT_DIR/notes.txt"
REPO_LIB_STEP_REGEX=$(cat <<'NIXEOF'
^version=.*$
NIXEOF
)
REPO_LIB_STEP_REPLACEMENT=$(cat <<NIXEOF
version=$FULL_VERSION
NIXEOF
)
export REPO_LIB_STEP_REGEX REPO_LIB_STEP_REPLACEMENT
perl -0pi -e 'my $regex = $ENV{"REPO_LIB_STEP_REGEX"}; my $replacement = $ENV{"REPO_LIB_STEP_REPLACEMENT"}; s/$regex/$replacement/gms;' "$target_path"
log "Updated notes.txt"

printf '%s\n' "$FULL_TAG" >"$ROOT_DIR/release.tag"
EOF

	read -r -d '' post_version <<'EOF' || true
printf '%s\n' "$FULL_VERSION" >"$ROOT_DIR/post-version.txt"
EOF

	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/repo"
	local remote_dir="$workdir/remote.git"
	CURRENT_LOG="$workdir/case.log"

	prepare_case_repo_with_release_script "$repo_dir" "$remote_dir" "$release_steps" "$post_version"
	printf 'version=old\n' >"$repo_dir/notes.txt"
	run_capture_ok "$case_name: setup commit failed" git -C "$repo_dir" add notes.txt
	run_capture_ok "$case_name: setup commit failed" git -C "$repo_dir" commit -m "chore: add notes"

	run_capture_ok "$case_name: release command failed" run_release "$repo_dir" patch

	assert_eq "1.0.1" "$(version_from_file "$repo_dir")" "$case_name: VERSION mismatch"
	assert_eq "1.0.1" "$(tr -d '\r' <"$repo_dir/generated/version.txt")" "$case_name: generated version file mismatch"
	assert_eq "version=1.0.1" "$(tr -d '\r' <"$repo_dir/notes.txt")" "$case_name: replace step mismatch"
	assert_eq "v1.0.1" "$(tr -d '\r' <"$repo_dir/release.tag")" "$case_name: run step mismatch"
	assert_eq "1.0.1" "$(tr -d '\r' <"$repo_dir/post-version.txt")" "$case_name: postVersion mismatch"

	if ! git -C "$repo_dir" tag --list | grep -qx "v1.0.1"; then
		fail "$case_name: expected tag v1.0.1 was not created"
	fi

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_version_metadata_case() {
	local case_name="release metadata is preserved and exported"
	local release_steps

	read -r -d '' release_steps <<'EOF' || true
if [[ "$(version_meta_get desktop_backend_change_scope)" != "bindings" ]]; then
	echo "metadata getter mismatch" >&2
	exit 1
fi
if [[ "${VERSION_META_DESKTOP_BACKEND_CHANGE_SCOPE:-}" != "bindings" ]]; then
	echo "metadata export mismatch" >&2
	exit 1
fi
if [[ "${VERSION_META_DESKTOP_RELEASE_MODE:-}" != "binary" ]]; then
	echo "metadata export mismatch" >&2
	exit 1
fi

	version_meta_set desktop_release_mode codepush
	version_meta_set desktop_binary_version_min 1.0.0
	version_meta_set desktop_binary_version_max "$FULL_VERSION"
	version_meta_set desktop_backend_compat_id compat-123
	version_meta_unset desktop_unused
EOF

	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/repo"
	local remote_dir="$workdir/remote.git"
	CURRENT_LOG="$workdir/case.log"

	prepare_case_repo_with_release_script "$repo_dir" "$remote_dir" "$release_steps" ":"
	cat >"$repo_dir/VERSION" <<'EOF'
1.0.0
stable
0
desktop_backend_change_scope=bindings
desktop_release_mode=binary
desktop_unused=temporary
EOF
	run_capture_ok "$case_name: setup commit failed" git -C "$repo_dir" add VERSION
	run_capture_ok "$case_name: setup commit failed" git -C "$repo_dir" commit -m "chore: seed metadata"
	run_capture_ok "$case_name: release command failed" run_release "$repo_dir" patch

	assert_eq "1.0.1" "$(version_from_file "$repo_dir")" "$case_name: VERSION mismatch"
	assert_contains "desktop_backend_change_scope=bindings" "$repo_dir/VERSION" "$case_name: missing preserved scope"
	assert_contains "desktop_release_mode=codepush" "$repo_dir/VERSION" "$case_name: missing updated mode"
	assert_contains "desktop_binary_version_min=1.0.0" "$repo_dir/VERSION" "$case_name: missing min version"
	assert_contains "desktop_binary_version_max=1.0.1" "$repo_dir/VERSION" "$case_name: missing max version"
	assert_contains "desktop_backend_compat_id=compat-123" "$repo_dir/VERSION" "$case_name: missing compat id"
	if grep -Fq "desktop_unused=temporary" "$repo_dir/VERSION"; then
		fail "$case_name: unset metadata key was preserved"
	fi

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_mk_repo_case() {
	local case_name="mkRepo exposes outputs and auto-installs tools"
	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/mk-repo"
	mkdir -p "$repo_dir"
	write_mk_repo_flake "$repo_dir"
	CURRENT_LOG="$workdir/mk-repo.log"

	run_capture_ok "$case_name: flake show failed" nix flake show --json --no-write-lock-file "$repo_dir"
	assert_contains '"lefthook-check"' "$CURRENT_LOG" "$case_name: missing lefthook-check"
	assert_contains '"release"' "$CURRENT_LOG" "$case_name: missing release package"
	assert_contains '"example"' "$CURRENT_LOG" "$case_name: missing merged package"

	run_capture_ok "$case_name: tool package should be available in shell" bash -c 'cd "$1" && nix develop --no-write-lock-file . -c hello --version' _ "$repo_dir"
	run_capture_ok "$case_name: release package should be available in shell" bash -c 'cd "$1" && nix develop --no-write-lock-file . -c sh -c "command -v release >/dev/null"' _ "$repo_dir"

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_mk_repo_command_tool_case() {
	local case_name="mkRepo supports command-backed tools from PATH"
	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/mk-repo-command-tool"
	mkdir -p "$repo_dir"
	write_mk_repo_command_tool_flake "$repo_dir"
	CURRENT_LOG="$workdir/mk-repo-command-tool.log"

	run_capture_ok "$case_name: flake show failed" nix flake show --json --no-write-lock-file "$repo_dir"
	assert_contains '"lefthook-check"' "$CURRENT_LOG" "$case_name: missing lefthook-check"
	assert_contains '"release"' "$CURRENT_LOG" "$case_name: missing release package"

	run_capture_ok "$case_name: system nix should be available in shell" bash -c 'cd "$1" && nix develop --no-write-lock-file . -c nix --version' _ "$repo_dir"
	assert_contains "" "$CURRENT_LOG" "$case_name: missing tool icon in banner"
	run_capture_ok "$case_name: release package should be available in shell" bash -c 'cd "$1" && nix develop --no-write-lock-file . -c sh -c "command -v release >/dev/null"' _ "$repo_dir"

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_mk_repo_lefthook_case() {
	local case_name="mkRepo exposes raw lefthook config for advanced hook fields"
	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/mk-repo-lefthook"
	local system
	local derivation_json="$workdir/lefthook-run.drv.json"
	local lefthook_yml_drv
	local lefthook_yml_json="$workdir/lefthook-yml.drv.json"
	mkdir -p "$repo_dir"
	write_mk_repo_lefthook_flake "$repo_dir"
	CURRENT_LOG="$workdir/mk-repo-lefthook.log"

	system="$(nix eval --raw --impure --expr 'builtins.currentSystem')"
	run_capture_ok "$case_name: flake show failed" nix flake show --json --no-write-lock-file "$repo_dir"
	run_capture_ok "$case_name: lefthook derivation show failed" bash -c 'nix derivation show "$1" >"$2"' _ "$repo_dir#checks.${system}.lefthook-check" "$derivation_json"

	lefthook_yml_drv="$(perl -0ne 'print "/nix/store/$1\n" if /"([a-z0-9]{32}-lefthook\.yml\.drv)"/' "$derivation_json")"
	if [[ -z "$lefthook_yml_drv" ]]; then
		fail "$case_name: could not locate lefthook.yml derivation"
	fi

	run_capture_ok "$case_name: lefthook.yml derivation show failed" bash -c 'nix derivation show "$1" >"$2"' _ "$lefthook_yml_drv" "$lefthook_yml_json"
	assert_contains '\"pre-push\":{\"commands\":{\"tests\":{' "$lefthook_yml_json" "$case_name: generated check missing from pre-push"
	assert_contains 'repo-lib-check-tests' "$lefthook_yml_json" "$case_name: generated check command missing from lefthook config"
	assert_contains '\"output\":[\"failure\",\"summary\"]' "$lefthook_yml_json" "$case_name: lefthook output config missing"
	assert_contains '\"stage_fixed\":true' "$lefthook_yml_json" "$case_name: stage_fixed missing from lefthook config"

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_mk_repo_treefmt_hook_case() {
	local case_name="mkRepo configures treefmt and lefthook for dev shell hooks"
	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/mk-repo-treefmt"
	local system
	local derivation_json="$workdir/treefmt-hook.drv.json"
	local lefthook_yml_drv
	local lefthook_yml_json="$workdir/treefmt-hook-yml.drv.json"
	mkdir -p "$repo_dir"
	write_mk_repo_flake "$repo_dir"
	CURRENT_LOG="$workdir/mk-repo-treefmt.log"

	init_git_repo "$repo_dir"

	run_capture_ok "$case_name: treefmt should be available in shell" bash -c 'cd "$1" && nix develop --no-write-lock-file . -c sh -c '"'"'printf "%s\n" "$LEFTHOOK_BIN" && command -v treefmt'"'"'' _ "$repo_dir"
	assert_contains 'lefthook-dumb-term' "$CURRENT_LOG" "$case_name: LEFTHOOK_BIN wrapper missing"
	assert_contains '/bin/treefmt' "$CURRENT_LOG" "$case_name: treefmt missing from shell"

	system="$(nix eval --raw --impure --expr 'builtins.currentSystem')"
	run_capture_ok "$case_name: formatting check derivation show failed" bash -c 'nix derivation show "$1" >"$2"' _ "$repo_dir#checks.${system}.formatting-check" "$workdir/formatting-check.drv.json"
	run_capture_ok "$case_name: lefthook derivation show failed" bash -c 'nix derivation show "$1" >"$2"' _ "$repo_dir#checks.${system}.lefthook-check" "$derivation_json"

	lefthook_yml_drv="$(perl -0ne 'print "/nix/store/$1\n" if /"([a-z0-9]{32}-lefthook\.yml\.drv)"/' "$derivation_json")"
	if [[ -z "$lefthook_yml_drv" ]]; then
		fail "$case_name: could not locate lefthook.yml derivation"
	fi

	run_capture_ok "$case_name: lefthook.yml derivation show failed" bash -c 'nix derivation show "$1" >"$2"' _ "$lefthook_yml_drv" "$lefthook_yml_json"
	assert_contains '--no-cache {staged_files}' "$lefthook_yml_json" "$case_name: treefmt hook missing staged-file format command"
	assert_contains '\"stage_fixed\":true' "$lefthook_yml_json" "$case_name: treefmt hook should re-stage formatted files"

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_mk_repo_tool_failure_case() {
	local case_name="mkRepo required tools fail shell startup"
	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/tool-failure"
	mkdir -p "$repo_dir"
	write_tool_failure_flake "$repo_dir"
	CURRENT_LOG="$workdir/tool-failure.log"

	run_expect_failure "$case_name: shell startup should fail" bash -c 'cd "$1" && nix develop . -c true' _ "$repo_dir"
	assert_contains "probe failed" "$CURRENT_LOG" "$case_name: failure reason missing"

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_impure_bootstrap_validation_case() {
	local case_name="mkRepo rejects bootstrap without explicit opt-in"
	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/bootstrap-validation"
	mkdir -p "$repo_dir"
	write_impure_bootstrap_flake "$repo_dir"
	CURRENT_LOG="$workdir/bootstrap-validation.log"

	run_expect_failure "$case_name: evaluation should fail" nix flake show --json "$repo_dir"
	assert_contains "allowImpureBootstrap" "$CURRENT_LOG" "$case_name: validation message missing"

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_legacy_api_eval_case() {
	local case_name="legacy mkDevShell and mkRelease still evaluate"
	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/legacy"
	mkdir -p "$repo_dir"
	write_legacy_flake "$repo_dir"
	CURRENT_LOG="$workdir/legacy.log"

	run_capture_ok "$case_name: flake show failed" nix flake show --json "$repo_dir"
	assert_contains '"lefthook-check"' "$CURRENT_LOG" "$case_name: missing lefthook-check"
	assert_contains '"release"' "$CURRENT_LOG" "$case_name: missing release package"

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_template_eval_case() {
	local case_name="template flake evaluates with mkRepo"
	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/template"
	mkdir -p "$repo_dir"
	write_template_fixture "$repo_dir"
	CURRENT_LOG="$workdir/template.log"

	if [[ ! -f "$repo_dir/package.json" ]]; then
		fail "$case_name: template fixture missing package.json"
	fi
	if [[ ! -f "$repo_dir/.moon/workspace.yml" ]]; then
		fail "$case_name: template fixture missing .moon/workspace.yml"
	fi

	run_capture_ok "$case_name: flake show failed" nix flake show --json "$repo_dir"
	assert_contains '"lefthook-check"' "$CURRENT_LOG" "$case_name: missing lefthook-check"
	assert_contains '"release"' "$CURRENT_LOG" "$case_name: missing release package"

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_release_replace_backref_case() {
	local case_name="mkRepo release replace supports sed-style backrefs"
	local workdir
	workdir="$(mktemp -d)"
	local repo_dir="$workdir/repo"
	local remote_dir="$workdir/remote.git"
	CURRENT_LOG="$workdir/release-backref.log"

	setup_repo "$repo_dir" "$remote_dir"
	mkdir -p "$repo_dir/template"
	cat >"$repo_dir/template/flake.nix" <<'EOF'
{
  inputs = {
    repo-lib.url = "git+https://git.dgren.dev/eric/nix-flake-lib?ref=refs/tags/v0.0.0";
  };
}
EOF
	write_release_replace_backref_flake "$repo_dir"
	run_capture_ok "$case_name: setup commit failed" git -C "$repo_dir" add flake.nix template/flake.nix
	run_capture_ok "$case_name: setup commit failed" git -C "$repo_dir" commit -m "chore: add replace fixture"

	run_capture_ok "$case_name: nix run release failed" bash -c 'cd "$1" && nix run --no-write-lock-file .#release -- patch' _ "$repo_dir"

	assert_contains 'repo-lib.url = "git+https://example.invalid/repo-lib?ref=refs/tags/v1.0.1";' "$repo_dir/template/flake.nix" "$case_name: replacement did not preserve captures"
	if grep -Fq '\1git+https://example.invalid/repo-lib?ref=refs/tags/v1.0.1\2' "$repo_dir/template/flake.nix"; then
		fail "$case_name: replacement left literal backreferences in output"
	fi

	rm -rf "$workdir"
	CURRENT_LOG=""
	echo "[test] PASS: $case_name" >&2
}

run_case "channel-only from stable bumps patch" "beta" "1.0.1-beta.1"
run_case "explicit minor bump keeps requested bump" "minor beta" "1.1.0-beta.1"
run_set_prerelease_then_full_case
run_stable_then_beta_cannot_reuse_same_base_case
run_set_stable_then_full_noop_case
run_set_stable_from_prerelease_requires_full_case
run_patch_stable_from_prerelease_requires_full_case
run_structured_release_steps_case
run_version_metadata_case
run_mk_repo_case
run_mk_repo_command_tool_case
run_mk_repo_lefthook_case
run_mk_repo_treefmt_hook_case
run_mk_repo_tool_failure_case
run_impure_bootstrap_validation_case
run_legacy_api_eval_case
run_template_eval_case
run_release_replace_backref_case
if [[ "${QUICKCHECK:-0}" == "1" ]]; then
	run_randomized_quickcheck_cases
fi

echo "[test] All release tests passed" >&2
